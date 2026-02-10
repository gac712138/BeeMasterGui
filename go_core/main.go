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
	adapter      = bluetooth.DefaultAdapter
	foundDevices = make(map[string]string)
	scanMutex    sync.Mutex

	// 🔥 參考 CLI 核心機制：紀錄每個 MAC 的斷點 Offset 與完成狀態
	deviceOffsetMap = make(map[string]int)
	deviceDoneMap   = make(map[string]bool)
	progressMutex   sync.Mutex

	TargetID     string
	TargetFile   string
	FileMetaData FileMeta
)

const (
	STATUS_SUCCESS = iota
	STATUS_REBURN
	STATUS_RELEASE
)

// --- Flutter 溝通介面 ---

func reportLog(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("LOG:%s\n", msg)
}

func reportProgress(mac string, pct int) {
	fmt.Printf("PROGRESS:%s:%d\n", mac, pct)
}

func reportError(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	fmt.Printf("ERROR:%s\n", msg)
	os.Exit(1)
}

// --- 主程式 ---

func main() {
	targetPtr := flag.String("target", "", "Target ID")
	filePtr := flag.String("file", "", "ADS File")
	flag.Parse()

	TargetID, TargetFile = *targetPtr, *filePtr
	FileMetaData = ParseADSFile(TargetFile)

	workerPorts := FindDonglePorts()
	adapter.Enable()

	jobQueue := make(chan Job, 100)
	for _, port := range workerPorts {
		go productionWorker(port, jobQueue)
	}

	go StartIDScanner(TargetID, jobQueue)
	select {}
}

// --- 邏輯組件 ---

func StartIDScanner(targetID string, queue chan Job) {
	adapter.Scan(func(adapter *bluetooth.Adapter, result bluetooth.ScanResult) {
		name, mac := result.LocalName(), result.Address.String()
		if name == "" || !strings.Contains(name, targetID) {
			return
		}

		scanMutex.Lock()
		if _, exists := foundDevices[mac]; !exists {
			progressMutex.Lock()
			// 🔥 核心修復：讀取該 MAC 的「斷點進度」
			lastOffset := deviceOffsetMap[mac]
			isDone := deviceDoneMap[mac]
			progressMutex.Unlock()

			foundDevices[mac] = name
			queue <- Job{
				Name: name, MAC: mac,
				CurrentOffset: lastOffset, // 帶入斷點
				SkipBurn:      isDone,     // 帶入接力狀態
			}
		}
		scanMutex.Unlock()
	})
}

func productionWorker(port string, jobs chan Job) {
	t := NewSerialAdaptor(port)
	for job := range jobs {
		prefix := fmt.Sprintf("[%s|%s]", port, job.Name)
		for {
			status := func() int {
				defer t.Disconnect()

				// 1. 斷點續傳燒錄
				if !job.SkipBurn {
					if !PerformFlash(t, job.MAC, FileMetaData, prefix, &job.CurrentOffset) {
						// 🔥 關鍵：燒錄中斷時，立即存回目前的 Offset
						markDeviceProgress(job.MAC, job.CurrentOffset, false)
						return STATUS_RELEASE
					}
					if !VerifyChecksumAndReboot(t, FileMetaData, prefix) {
						return STATUS_RELEASE
					}

					markDeviceProgress(job.MAC, 0, true) // 燒完 100%，標記 Done
					t.Disconnect()
					reportLog("%s 🛌 設備重啟，等待 15s...", prefix)
					time.Sleep(15 * time.Second)
				} else {
					reportLog("%s ⏩ 偵測到已燒錄完成，接力執行檢查...", prefix)
				}

				// 2. 強化握手連線 (參考 CLI 重連)
				connected := false
				for r := 0; r < 5; r++ {
					if err := t.Connect(job.MAC); err == nil {
						connected = true
						break
					}
					time.Sleep(2 * time.Second)
				}
				if !connected {
					return STATUS_RELEASE
				}

				// 3. 執行檢查 (使用強化後的 debug_reader.go)
				match, err := PerformFinalDebugCheck(t, FileMetaData, prefix)
				if err != nil {
					return STATUS_RELEASE
				} // 解鎖失敗 -> 釋放任務

				if !match {
					clearDeviceProgress(job.MAC) // 內容錯了 -> 徹底重來
					return STATUS_REBURN
				}

				var f uint16
				t.SendCmd(0x20, &f, []byte{0xE4, 0x00, 0x01})
				return STATUS_SUCCESS
			}()

			if status == STATUS_SUCCESS {
				break
			}
			if status == STATUS_REBURN {
				job.CurrentOffset, job.SkipBurn = 0, false
				continue
			}
			releaseDevice(job.MAC)
			break
		}
	}
}

// --- 狀態管理輔助函式 ---

func markDeviceProgress(mac string, offset int, done bool) {
	progressMutex.Lock()
	deviceOffsetMap[mac], deviceDoneMap[mac] = offset, done
	progressMutex.Unlock()
}

// 🔥 修正這裡：將 deviceProgress 改為 deviceDoneMap
func isDeviceBurned(mac string) bool {
	progressMutex.Lock()
	defer progressMutex.Unlock()
	return deviceDoneMap[mac]
}

func clearDeviceProgress(mac string) {
	progressMutex.Lock()
	delete(deviceOffsetMap, mac)
	delete(deviceDoneMap, mac)
	progressMutex.Unlock()
}

func releaseDevice(mac string) {
	scanMutex.Lock()
	delete(foundDevices, mac)
	scanMutex.Unlock()
}
