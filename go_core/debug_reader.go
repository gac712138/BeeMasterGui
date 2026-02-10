package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"time"
)

// PerformFinalDebugCheck 執行最終的一致性比對
func PerformFinalDebugCheck(t Transporter, meta FileMeta, prefix string) (bool, error) {
	reportLog("%s ⚖️  === 正在啟動語音一致性比對 ===", prefix)

	reportLog("%s ⏳ 正在緩衝連線，等待 10 秒...", prefix)
	time.Sleep(10 * time.Second)

	// 1. 顯示本地檔案資訊
	if len(meta.RawData) < 606 {
		return false, fmt.Errorf("本地檔案資料不足")
	}
	_, localTracks := parseHeaderBytes(meta.RawData[:606], "Local ADS", prefix)

	// 解鎖設備
	reportLog("%s  正在解鎖設備 (Set Engineering Mode)...", prefix)
	if !unlockDevice(t, prefix) {
		reportLog("%s ❌ 讀取設備失敗，無法讀取語音", prefix)
		return false, fmt.Errorf("解鎖失敗") // 這裡回傳 error，main.go 會執行 RELEASE
	}

	// 2. 讀取設備資訊
	reportLog("%s 📥 === 正在讀取資料 (分頁讀取) ===", prefix)

	deviceTracks := performPagedRead(t, prefix)

	// 🔥 優化 1：如果讀取不到資料 (nil) 或資料是空的 (empty)，視為讀取失敗
	// 這樣 main.go 會執行 STATUS_RELEASE (換 Dongle)，而不是 STATUS_REBURN
	if deviceTracks == nil {
		reportLog("%s ❌ 讀取設備失敗 (無資料或連線中斷)", prefix)
		return false, fmt.Errorf("無法讀取設備")
	}

	// 3. 執行比對
	match := performComparisonModular(localTracks, deviceTracks, prefix)
	return match, nil
}

// unlockDevice (保持不變)
func unlockDevice(t Transporter, prefix string) bool {
	var f uint16 = 0
	for i := 0; i < 3; i++ {
		t.ResetBuffer()
		t.SendCmd(0x20, &f, []byte{0xE6, 0x01})
		if err := t.WaitForACK(2 * time.Second); err == nil {
			return true
		}
		// 建議改為：每次失敗都等一秒，給設備喘息機會
		reportLog("%s 嘗試讀取語音失敗 %d/3 ，等待 2s...", prefix, i+1)
		time.Sleep(2 * time.Second)
	}
	return false
}

// performPagedRead (保持不變)
func performPagedRead(t Transporter, prefix string) map[int]TrackInfo {
	payloadBuffer := make([]byte, 0, 1024)
	rawBuffer := make([]byte, 0, 4096)
	magicCode := []byte{0x27, 0x9D}
	targetSize := 606
	chunkSize := 192
	totalDeadline := time.Now().Add(25 * time.Second)
	currentOffset := 0

	for len(payloadBuffer) < targetSize {
		if time.Now().After(totalDeadline) {
			reportLog("%s ❌ 讀取總時長超時", prefix)
			break
		}
		needed := targetSize - len(payloadBuffer)
		reqSize := chunkSize
		if needed < reqSize {
			reqSize = needed
		}

		sendReadCommand(t, currentOffset, reqSize)
		chunkDeadline := time.Now().Add(2500 * time.Millisecond)
		chunkReceived := false

		for time.Now().Before(chunkDeadline) {
			chunk, err := t.ReadResponse(50 * time.Millisecond)
			if err == nil && len(chunk) > 0 {
				rawBuffer = append(rawBuffer, chunk...)
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
					}

					payload := rawBuffer[8 : 8+payloadLen]
					if len(payload) > 0 && payload[0] == 0xC7 {
						realData := payload[1:]
						payloadBuffer = append(payloadBuffer, realData...)
						currentOffset += len(realData)
						chunkReceived = true
					}
					rawBuffer = rawBuffer[packetLen:]
				}
				if chunkReceived {
					break
				}
			}
		}

		if !chunkReceived {
			reportLog("%s ⚠️ 讀取超時，重試 Offset: %d...", prefix, currentOffset)
		} else {
			time.Sleep(100 * time.Millisecond)
		}
	}

	idx := bytes.Index(payloadBuffer, magicCode)
	if idx != -1 {
		if len(payloadBuffer) >= idx+606 {
			reportLog("%s ✨ 讀取完成 (%d bytes)！解析中...", prefix, len(payloadBuffer))
			headerData := payloadBuffer[idx : idx+606]
			_, tracks := parseHeaderBytes(headerData, "Device ADS", prefix)
			return tracks
		}
	}
	reportLog("%s [Debug] 最終 Buffer 長度: %d (Hex: %s...)", prefix, len(payloadBuffer), hex.EncodeToString(safeSlice(payloadBuffer, 20)))
	return nil
}

func safeSlice(b []byte, n int) []byte {
	if len(b) > n {
		return b[:n]
	}
	return b
}

func sendReadCommand(t Transporter, offset int, size int) {
	t.ResetBuffer()
	var f uint16 = 0
	readCmd := make([]byte, 0, 7)
	readCmd = append(readCmd, 0xC6)
	readCmd = append(readCmd, byte(offset&0xff), byte((offset>>8)&0xff), byte((offset>>16)&0xff), byte((offset>>24)&0xff))
	readCmd = append(readCmd, byte(size&0xff), byte((size>>8)&0xff))
	t.SendCmd(0x20, &f, readCmd)
}

// performComparisonModular 執行比對並輸出 Flutter 可解析的 Log
func performComparisonModular(local, device map[int]TrackInfo, prefix string) bool {
	reportLog("%s 📋 --- 比對結果報告 ---", prefix)
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

		status := "MATCH"
		lid, lsize := l.ID, l.Size
		did, dsize := d.ID, d.Size

		isLocalEmpty := (lid == 0 && lsize == 0)
		isDevEmpty := (did == 0 && dsize == 0)

		if isLocalEmpty && isDevEmpty {
			status = "EMPTY"
		} else if lid != did {
			status = "ID_MISMATCH"
			allMatch = false
		} else if lsize != dsize {
			status = "SIZE_MISMATCH"
			allMatch = false
		}

		// 一般 Log 供 Console 觀看
		// reportLog("%s %02d | %d | %d | %s", prefix, i, lid, did, status)

		// 🔥 優化 2：輸出特殊格式 Log 供 Flutter 解析
		// 格式: TRACK_DETAIL:Index:ID:Size:Status
		if status == "MATCH" {
			// 只有 Match 的才需要顯示給使用者看
			reportLog("TRACK_DETAIL:%d:%d:%d", i, did, dsize)
		}
	}

	if allMatch {
		reportLog("%s 🎉 比對成功！內容一致。", prefix)
	} else {
		reportLog("%s ⚠️ 比對失敗！請檢查上述報告。", prefix)
	}

	return allMatch
}
