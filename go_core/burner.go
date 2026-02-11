package main

import (
	"fmt"
	"time"
)

// PerformFlash 依照 Dart Protocol 流程修正
func PerformFlash(t Transporter, mac string, meta FileMeta, prefix string, offset *int) bool {
	totalSize := len(meta.EncodedData)
	if totalSize == 0 {
		return false
	}
	currentOffset := *offset
	var f uint16 = 0

	// 1. 連線
	reportLog("%s ⏳ 連線中 (Hardware Reset)...\n", prefix)
	if err := t.Connect(mac); err != nil {
		reportLog("%s ❌ 連線失敗: %v\n", prefix, err)
		return false
	}

	// 2. 解鎖 (Set Operation Mode Engineering)
	reportLog("%s 🔓 解鎖 (Unlock)...", prefix)
	t.ResetBuffer()
	t.SendCmd(0x20, &f, []byte{0xE6, 0x01})

	// 等待 ACK
	if err := t.WaitForACK(2 * time.Second); err != nil {
		// 嘗試重發一次
		reportLog("%s ⚠️ 解鎖無回應，重試...\n", prefix)
		t.SendCmd(0x20, &f, []byte{0xE6, 0x01})
		if err := t.WaitForACK(2 * time.Second); err != nil {
			reportLog("%s ❌ 解鎖失敗: %v\n", prefix, err)
			return false
		}
	}
	time.Sleep(200 * time.Millisecond)

	// 🔥 關鍵步驟: 初始化 Checksum (參考 Dart Protocol)
	// Dart: _writeAudioData(604, 2, [0xff, 0xff])
	//reportLog("%s 🧹 發送初始化指令 (Write FF to 604)...\n", prefix)
	t.ResetBuffer()
	initErr := t.SendAudioChunk(&f, 604, []byte{0xFF, 0xFF})
	if initErr != nil {
		reportLog("%s ❌ 初始化發送失敗\n", prefix)
		return false
	}

	if err := t.WaitForACK(2 * time.Second); err != nil {
		reportLog("%s ⚠️ 初始化指令無回應 (可能未就緒): %v\n", prefix, err)
		return false
	}
	time.Sleep(200 * time.Millisecond)

	// 3. 燒錄
	reportLog("%s 🔥 開始燒錄 (Total: %d bytes)...", prefix, totalSize)
	const ChunkSize = 192

	lastPct := -1

	for currentOffset < totalSize {
		end := currentOffset + ChunkSize
		if end > totalSize {
			end = totalSize
		}

		chunkData := meta.EncodedData[currentOffset:end]

		// 單包重試機制
		packetSuccess := false
		packetRetries := 0
		const MaxPacketRetries = 5

		for packetRetries < MaxPacketRetries {
			t.ResetBuffer()

			err := t.SendAudioChunk(&f, currentOffset, chunkData)
			if err != nil {
				return false
			}

			ackErr := t.WaitForACK(1500 * time.Millisecond)

			if ackErr == nil {
				packetSuccess = true
				break
			} else {
				packetRetries++
				if packetRetries >= 2 {
					reportLog("%s ⚠️ Offset %d ACK 超時，重傳 (%d/%d)...\n", prefix, currentOffset, packetRetries, MaxPacketRetries)
				}
				time.Sleep(200 * time.Millisecond)
			}
		}

		if !packetSuccess {
			reportLog("%s ❌ 燒錄失敗：Offset %d 連續無回應\n", prefix, currentOffset)
			return false
		}

		currentOffset += (end - currentOffset)
		*offset = currentOffset

		pct := int(float64(currentOffset) / float64(totalSize) * 100)
		if (pct > lastPct && pct%5 == 0) || currentOffset == totalSize {

			reportProgress(mac, pct)
			reportLog("LOG:%s ⏳ 進度: %d%% (%d/%d)\n", prefix, pct, currentOffset, totalSize)
			lastPct = pct
		}

		time.Sleep(50 * time.Millisecond)
	}
	return true
}

func VerifyChecksumAndReboot(t Transporter, meta FileMeta, prefix string) bool {
	var f uint16 = 0
	fmt.Printf("%s 🔐 Checksum 驗證中...\n", prefix)

	// 發送 604 與 605 位置的真實校驗碼
	chkBytes := meta.RawData[604:606]
	t.SendAudioChunk(&f, 604, chkBytes)

	if err := t.WaitForACK(3 * time.Second); err != nil {
		fmt.Printf("%s ❌ Checksum 失敗\n", prefix)
		return false
	}

	// 下達重啟 (OpCode 0xE4) 指令 3 次
	fmt.Printf("%s 🔄 發送重啟指令...\n", prefix)
	for k := 0; k < 3; k++ {
		t.SendCmd(0x20, &f, []byte{0xE4, 0x00, 0x01})
		time.Sleep(200 * time.Millisecond)
	}
	return true
}
