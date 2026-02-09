package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"os"
	"text/tabwriter"
	"time"
)

// PerformFinalDebugCheck 執行最終的一致性比對
func PerformFinalDebugCheck(t Transporter, meta FileMeta, prefix string) (bool, error) {
	reportLog("%s ⚖️  === 啟動語音一致性比對 ===\n", prefix)
	reportLog("%s 🤝 === 連線成功 (握手完成) ===\n", prefix)

	reportLog("%s ⏳ 正在緩衝連線，等待 10 秒...\n", prefix)
	time.Sleep(10 * time.Second)

	// 1. 顯示本地檔案資訊
	if len(meta.RawData) < 606 {
		return false, fmt.Errorf("本地檔案資料不足 (<606 bytes)")
	}
	_, localTracks := parseHeaderBytes(meta.RawData[:606], "Local ADS", prefix)

	// 解鎖設備
	reportLog("%s 🔓 正在解鎖設備 (Set Engineering Mode)...\n", prefix)
	if !unlockDevice(t, prefix) {
		reportLog("%s ❌ 解鎖失敗，無法讀取\n", prefix)
		return false, fmt.Errorf("解鎖失敗")
	}

	// 2. 讀取設備資訊 (使用分頁讀取)
	reportLog("%s 📥 === 正在讀取資料 (分頁讀取 192 bytes/page) ===\n", prefix)

	deviceTracks := performPagedRead(t, prefix)
	fmt.Printf("\n")

	if deviceTracks == nil {
		reportLog("%s ❌ 讀取設備失敗 (資料不完整)\n", prefix)
		return false, fmt.Errorf("無法讀取設備")
	}

	// 3. 執行比對
	match := performComparisonModular(localTracks, deviceTracks, prefix)
	return match, nil
}

// unlockDevice 發送 0xE6 指令並等待確認
func unlockDevice(t Transporter, prefix string) bool {
	var f uint16 = 0
	for i := 0; i < 3; i++ {
		t.ResetBuffer()
		t.SendCmd(0x20, &f, []byte{0xE6, 0x01})
		if err := t.WaitForACK(2 * time.Second); err == nil {
			return true
		} else {
			if i < 2 {
				time.Sleep(500 * time.Millisecond)
			}
		}
	}
	return false
}

// performPagedRead 分頁讀取：每次讀取 ChunkSize，直到湊齊 TargetSize
func performPagedRead(t Transporter, prefix string) map[int]TrackInfo {
	payloadBuffer := make([]byte, 0, 1024)
	rawBuffer := make([]byte, 0, 4096) // 用於暫存 0xC7 封包片段

	magicCode := []byte{0x27, 0x9D}
	targetSize := 606
	chunkSize := 192 // 依照 Dart Protocol 設定

	// 總超時時間
	totalDeadline := time.Now().Add(25 * time.Second)

	// 當前請求的參數
	currentOffset := 0

	for len(payloadBuffer) < targetSize {
		if time.Now().After(totalDeadline) {
			reportLog("%s ❌ 讀取總時長超時", prefix)
			break
		}

		// 計算這次要讀多少
		needed := targetSize - len(payloadBuffer)
		reqSize := chunkSize
		if needed < reqSize {
			reqSize = needed
		}

		// 發送讀取指令
		// fmt.Printf("\n%s 📤 請求 Offset: %d, Size: %d", prefix, currentOffset, reqSize)
		sendReadCommand(t, currentOffset, reqSize)

		// 等待這一塊資料回來 (小迴圈)
		chunkDeadline := time.Now().Add(2500 * time.Millisecond)
		chunkReceived := false

		for time.Now().Before(chunkDeadline) {
			chunk, err := t.ReadResponse(50 * time.Millisecond)
			if err == nil && len(chunk) > 0 {
				rawBuffer = append(rawBuffer, chunk...)

				// === 解析 0xC7 封包 ===
				// [25] [Target] ... [Len_L] [Len_H] [Payload(C7...)] [Checksum]
				for len(rawBuffer) > 8 {
					startIdx := bytes.IndexByte(rawBuffer, 0x25)
					if startIdx == -1 {
						if len(rawBuffer) > 5 {
							rawBuffer = rawBuffer[len(rawBuffer)-5:]
						}
						break
					}
					if startIdx > 0 {
						rawBuffer = rawBuffer[startIdx:]
					}
					if len(rawBuffer) < 8 {
						break
					}

					payloadLen := int(rawBuffer[6]) | (int(rawBuffer[7]) << 8)
					packetLen := 8 + payloadLen + 1

					if len(rawBuffer) < packetLen {
						break
					} // 等待更多資料

					// 提取 Payload
					payload := rawBuffer[8 : 8+payloadLen]

					// 檢查是否為 0xC7 回應
					if len(payload) > 0 && payload[0] == 0xC7 {
						realData := payload[1:] // 去掉 C7

						// 將資料加入主 Buffer
						payloadBuffer = append(payloadBuffer, realData...)
						currentOffset += len(realData)
						chunkReceived = true

						reportLog("%s .", prefix) // 進度點
					}

					// 移除已處理的封包
					rawBuffer = rawBuffer[packetLen:]
				}

				// 如果這一次請求的資料已經湊齊了，就跳出等待迴圈，進行下一次請求
				if chunkReceived {
					// 這裡做個簡單判斷：如果有收到資料，我們就假設這一輪 OK，
					// 讓外層迴圈去判斷長度是否足夠，不夠會再發新的 Offset 請求
					break
				}
			}
		}

		if !chunkReceived {
			fmt.Print("↻") // 超時重試符號
			// 不更新 currentOffset，外層迴圈會再次用同樣的 Offset 重發指令
		} else {
			// 稍微等一下再發下一個請求，避免塞爆
			time.Sleep(100 * time.Millisecond)
		}
	}

	// 讀取完成，開始解析
	idx := bytes.Index(payloadBuffer, magicCode)
	if idx != -1 {
		if len(payloadBuffer) >= idx+606 {
			reportLog("%s ✨ 讀取完成 (%d bytes)！解析中...\n", prefix, len(payloadBuffer))
			headerData := payloadBuffer[idx : idx+606]
			_, tracks := parseHeaderBytes(headerData, "Device ADS", prefix)
			return tracks
		}
	}

	reportLog("%s [Debug] 最終 PayloadBuffer 長度: %d (Hex: %s...)\n", prefix, len(payloadBuffer), hex.EncodeToString(safeSlice(payloadBuffer, 20)))
	return nil
}

func safeSlice(b []byte, n int) []byte {
	if len(b) > n {
		return b[:n]
	}
	return b
}

// sendReadCommand 發送 0xC6 讀取 Header (支援 Offset 和 Size)
func sendReadCommand(t Transporter, offset int, size int) {
	t.ResetBuffer()
	var f uint16 = 0

	// Payload: 0xC6 + Offset(4) + Size(2)
	readCmd := make([]byte, 0, 7)
	readCmd = append(readCmd, 0xC6)
	readCmd = append(readCmd, byte(offset&0xff), byte((offset>>8)&0xff), byte((offset>>16)&0xff), byte((offset>>24)&0xff))
	readCmd = append(readCmd, byte(size&0xff), byte((size>>8)&0xff))

	t.SendCmd(0x20, &f, readCmd)
}

func performComparisonModular(local, device map[int]TrackInfo, prefix string) bool {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintf(w, "%s No.\tLocal ID\tDev ID\tSize (L/D)\tResult\n", prefix)

	allMatch := true
	maxCheck := 50
	lastValid := 10

	for i := 1; i <= maxCheck; i++ {
		l := local[i]
		d := device[i]
		if l.ID != 0 || l.Size != 0 || d.ID != 0 || d.Size != 0 {
			lastValid = i
		}
	}

	for i := 1; i <= lastValid; i++ {
		l := local[i]
		d := device[i]

		status := "✅ Match"
		lid, lsize := l.ID, l.Size
		did, dsize := d.ID, d.Size

		isLocalEmpty := (lid == 0 && lsize == 0)
		isDevEmpty := (did == 0 && dsize == 0)

		if isLocalEmpty && isDevEmpty {
			status = "🔹 Empty"
		} else if lid != did {
			status = "❌ ID Mismatch"
			allMatch = false
		} else if lsize != dsize {
			status = "❌ Size Mismatch"
			allMatch = false
		}

		fmt.Fprintf(w, "%s %d\t%d\t%d\t%d / %d\t%s\n", prefix, i, lid, did, lsize, dsize, status)
	}
	w.Flush()

	if allMatch {
		reportLog("%s 🎉 比對成功！內容一致。\n", prefix)
	} else {
		reportLog("%s ⚠️ 比對失敗！請檢查上述表格。\n", prefix)
	}

	return allMatch
}
