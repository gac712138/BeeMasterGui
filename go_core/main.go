package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"tinygo.org/x/bluetooth"
)

// 全域變數
var (
	adapter        = bluetooth.DefaultAdapter
	foundDevices   = make(map[string]string)
	scanMutex      sync.Mutex
	deviceProgress = make(map[string]bool) // 紀錄已燒錄的 MAC
	progressMutex  sync.Mutex

	// 來自參數的設定
	TargetID     string
	TargetFile   string
	FileMetaData FileMeta
)

// 🔥 補回遺失的狀態常數
const (
	STATUS_SUCCESS = iota
	STATUS_REBURN
	STATUS_RELEASE
)

// --- Flutter 溝通介面 ---

// reportLog: 輸出格式化日誌，讓 Flutter 可以解析
func reportLog(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("LOG:%s\n", msg)
}

// reportProgress: 輸出進度 (給 Flutter 顯示進度條)
func reportProgress(mac string, pct int) {
	// 格式: PROGRESS:MAC_ADDRESS:PERCENT
	fmt.Printf("PROGRESS:%s:%d\n", mac, pct)
}

func reportError(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("ERROR:%s\n", msg)
	os.Exit(1)
}

// --- 主程式 ---

func main() {
	// 1. 接收參數 (由 Flutter 傳入)
	targetPtr := flag.String("target", "", "Target Device ID (substring, e.g. LLB)")
	filePtr := flag.String("file", "", "ADS File Path")
	flag.Parse()

	if *targetPtr == "" || *filePtr == "" {
		fmt.Println("Usage: worker.exe -target=LLB -file=firmware.ads")
		os.Exit(1)
	}
	TargetID = *targetPtr
	TargetFile = *filePtr

	reportLog("🚀 產線控制中心啟動 (Go Core)")
	reportLog("目標 ID: %s", TargetID)
	reportLog("燒錄檔案: %s", TargetFile)

	// 2. 自動掃描所有 Dongle
	// (呼叫 com_scanner.go 裡的方法)
	workerPorts := FindDonglePorts()
	if len(workerPorts) == 0 {
		reportError("未偵測到任何 Silicon Labs Dongle，請檢查 USB 連線")
		return
	}
	reportLog("已掛載 %d 支 Dongle: %v", len(workerPorts), workerPorts)

	// 3. 解析燒錄檔
	// (呼叫 ads_reader.go)
	FileMetaData = ParseADSFile(TargetFile)
	if FileMetaData.SizeKB == 0 {
		reportError("檔案解析失敗: %s", TargetFile)
		return
	}
	reportLog("檔案載入成功: %d KB (Tracks: %d)", FileMetaData.SizeKB, len(FileMetaData.Tracks))

	// 4. 啟用電腦藍牙 (用於掃描 ID)
	if err := adapter.Enable(); err != nil {
		reportError("電腦藍牙啟用失敗: %v", err)
		return
	}

	// 5. 啟動工作管線
	jobQueue := make(chan Job, 100)

	// 啟動所有 Dongle Workers
	for _, port := range workerPorts {
		go productionWorker(port, jobQueue)
	}

	// 啟動 ID 掃描器 (這是唯一的 Scanner)
	go StartIDScanner(TargetID, jobQueue)

	reportLog("✅ 系統全速運轉中... 等待目標出現")

	// 讓主程式不退出
	select {}
}

// --- 邏輯組件 ---

func StartIDScanner(targetID string, queue chan Job) {
	reportLog("📡 [Scanner] 啟動藍牙掃描，搜尋: %s...", targetID)

	// 避免重複 Log 的 cache
	// seenLog := make(map[string]bool)

	adapter.Scan(func(adapter *bluetooth.Adapter, result bluetooth.ScanResult) {
		name := result.LocalName()
		mac := result.Address.String()

		if name == "" {
			return
		}

		// 比對目標 ID
		if strings.Contains(name, targetID) {
			scanMutex.Lock()
			// 如果這個 MAC 還沒在佇列中
			if _, exists := foundDevices[mac]; !exists {
				// 檢查是否已經燒錄過 (避免重複燒錄)
				if isDeviceBurned(mac) {
					// 這裡可以決定是否要 skip，目前邏輯是燒過就不理它
				} else {
					foundDevices[mac] = name
					reportLog("🎯 [捕獲目標] %s (%s) | RSSI: %d", name, mac, result.RSSI)

					// 派發任務
					queue <- Job{
						Name:          name,
						MAC:           mac,
						CurrentOffset: 0,
						SkipBurn:      false,
					}
				}
			}
			scanMutex.Unlock()
		}
	})
}

func productionWorker(port string, jobs chan Job) {
	reportLog("🤖 工人 %s 就緒", port)

	// 每個工人有自己的 Serial Adaptor
	t := NewSerialAdaptor(port)

	for job := range jobs {
		prefix := fmt.Sprintf("[%s|%s]", port, job.Name)
		reportLog("%s 收到任務，準備執行...", prefix)

		// 狀態機迴圈
		for {
			status := func() int {
				// 確保結束後斷線
				defer t.Disconnect()

				// 1. 執行燒錄 (呼叫 flash.go)
				if !PerformFlash(t, job.MAC, FileMetaData, prefix, &job.CurrentOffset) {
					reportLog("%s ❌ 燒錄失敗 (Write Fail)", prefix)
					return STATUS_RELEASE
				}

				// 2. 驗證 Checksum
				if !VerifyChecksumAndReboot(t, FileMetaData, prefix) {
					reportLog("%s ❌ Checksum 驗證失敗", prefix)
					return STATUS_RELEASE
				}

				// 標記為已燒錄
				markDeviceBurned(job.MAC)

				t.Disconnect()
				reportLog("%s 🛌 設備重啟中 (等待 10s)...", prefix)
				time.Sleep(10 * time.Second)

				// 3. 最終比對 (呼叫 debug_reader.go)
				if err := t.Connect(job.MAC); err != nil {
					reportLog("%s ❌ 比對連線失敗", prefix)
					return STATUS_RELEASE
				}

				match, err := PerformFinalDebugCheck(t, FileMetaData, prefix)
				if err != nil {
					reportLog("%s ❌ 讀取資料失敗", prefix)
					return STATUS_RELEASE
				}

				if !match {
					reportLog("%s ⚠️ 比對不符 -> 原地重燒", prefix)
					clearDeviceProgress(job.MAC)
					job.SkipBurn = false
					return STATUS_REBURN
				}

				// 成功結束
				var f uint16
				t.SendCmd(0x20, &f, []byte{0xE4, 0x00, 0x01})
				return STATUS_SUCCESS
			}()

			// 處理狀態結果
			if status == STATUS_SUCCESS {
				reportLog("%s 🎉 任務圓滿完成！", prefix)
				break

			} else if status == STATUS_REBURN {
				reportLog("%s 🔄 重試中...", prefix)
				job.CurrentOffset = 0
				time.Sleep(2 * time.Second)
				continue

			} else {
				// 失敗釋放，讓 Scanner 可以再次掃描到它
				reportLog("%s ♻️ 任務失敗，釋放目標", prefix)
				releaseDevice(job.MAC)
				time.Sleep(2 * time.Second)
				break
			}
		}
	}
}

// --- 輔助狀態管理 ---

func markDeviceBurned(mac string) {
	progressMutex.Lock()
	deviceProgress[mac] = true
	progressMutex.Unlock()
}

func isDeviceBurned(mac string) bool {
	progressMutex.Lock()
	defer progressMutex.Unlock()
	return deviceProgress[mac]
}

func clearDeviceProgress(mac string) {
	progressMutex.Lock()
	delete(deviceProgress, mac)
	progressMutex.Unlock()
}

func releaseDevice(mac string) {
	scanMutex.Lock()
	delete(foundDevices, mac)
	scanMutex.Unlock()
}
