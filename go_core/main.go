package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"tinygo.org/x/bluetooth"
)

// TrackInfo 定義單一音軌資訊
type TrackInfo struct {
	ID     uint32
	Size   uint32
	Offset uint32
}

// FileMeta 定義 ADS 檔案的解析結果
type FileMeta struct {
	RawData     []byte
	EncodedData []byte
	SizeKB      int
	Tracks      map[int]TrackInfo
}

// Job 定義產線任務
type Job struct {
	Name          string
	MAC           string
	CurrentOffset int
	IsReburn      bool
	SkipBurn      bool
}

type Stats struct {
	TotalSuccess int
	TotalFailed  int
}

// --- 資料結構 (JSON 協議) ---
type Order struct {
	Command   string   `json:"command"`
	File      string   `json:"file"`
	TargetIDs []string `json:"target_ids"`
	Ports     []string `json:"ports"`
}

type Response struct {
	Type    string `json:"type"` // LOG, PROGRESS, ERROR
	Port    string `json:"port,omitempty"`
	Mac     string `json:"mac,omitempty"`
	Message string `json:"message,omitempty"`
	Pct     int    `json:"pct,omitempty"`
}

var (
	manager *FactoryManager
	adapter = bluetooth.DefaultAdapter
)

func main() {
	if err := adapter.Enable(); err != nil {
		sendError("SYSTEM", "藍牙啟用失敗: "+err.Error())
		return
	}
	listenToFlutter()
}

func listenToFlutter() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := scanner.Text()
		var order Order
		if err := json.Unmarshal([]byte(line), &order); err != nil {
			continue
		}

		if order.Command == "START" {
			if manager != nil {
				manager.Stop()
			}
			manager = NewFactoryManager(order)
			go manager.Start()
		} else if order.Command == "STOP" {
			if manager != nil {
				manager.Stop()
			}
		}
	}
}

// --- 🏭 廠長邏輯 ---

type FactoryManager struct {
	Config Order
	Meta   FileMeta

	IdlePorts chan string
	JobQueue  chan Job

	ProcessingMap map[string]bool
	DoneMap       map[string]bool
	OffsetMap     map[string]int
	MapMutex      sync.Mutex

	Quit chan bool
}

func NewFactoryManager(order Order) *FactoryManager {
	return &FactoryManager{
		Config:        order,
		Meta:          ParseADSFile(order.File),
		IdlePorts:     make(chan string, len(order.Ports)),
		JobQueue:      make(chan Job, 100),
		ProcessingMap: make(map[string]bool),
		DoneMap:       make(map[string]bool),
		OffsetMap:     make(map[string]int),
		Quit:          make(chan bool),
	}
}

func (m *FactoryManager) Start() {
	//sendLog("SYSTEM", fmt.Sprintf("🏭 工廠啟動，目標 ID: %v", m.Config.TargetIDs))

	for _, port := range m.Config.Ports {
		m.IdlePorts <- port
	}

	go m.RunGlobalScanner()
	go m.RunDispatcher()
}

func (m *FactoryManager) Stop() {
	close(m.Quit)
	sendLog("SYSTEM", "🛑 工廠已停工")
}

func (m *FactoryManager) RunGlobalScanner() {
	sendLog("SYSTEM", "👀 掃描器啟動...")
	adapter.Scan(func(adapter *bluetooth.Adapter, result bluetooth.ScanResult) {
		select {
		case <-m.Quit:
			adapter.StopScan()
			return
		default:
		}

		name := result.LocalName()
		mac := result.Address.String()

		matched := false
		for _, target := range m.Config.TargetIDs {
			if name != "" && strings.Contains(name, target) {
				matched = true
				break
			}
		}
		if !matched {
			return
		}

		m.MapMutex.Lock()
		if m.DoneMap[mac] || m.ProcessingMap[mac] {
			m.MapMutex.Unlock()
			return
		}

		m.ProcessingMap[mac] = true
		job := Job{
			Name:          name,
			MAC:           mac,
			CurrentOffset: m.OffsetMap[mac],
			SkipBurn:      false,
		}
		m.JobQueue <- job
		m.MapMutex.Unlock()
	})
}

func (m *FactoryManager) RunDispatcher() {
	for {
		select {
		case job := <-m.JobQueue:
			select {
			case port := <-m.IdlePorts:
				go m.RunWorker(port, job)
			case <-m.Quit:
				return
			}
		case <-m.Quit:
			return
		}
	}
}

func (m *FactoryManager) RunWorker(port string, job Job) {
	prefix := fmt.Sprintf("[%s][%s]", port, job.Name)

	// 🔥 FIX 1: 進場先檢查進度 (Checkpoint Check)
	// 如果上次已經燒完 (Offset == TotalSize)，直接設定 SkipBurn = true
	// 這樣接手的人就會直接跳去驗證，不會從頭重燒
	totalSize := len(m.Meta.EncodedData)
	if job.CurrentOffset >= totalSize && totalSize > 0 {
		job.SkipBurn = true
		sendLog(port, fmt.Sprintf("⚡ 偵測到已燒錄完成 (%s)，跳過燒錄，直接執行驗證...", job.Name))
	} else {
		sendLog(port, fmt.Sprintf("啟動作業: %s", job.Name))
	}

	sendProgress(port, job.MAC, 0) // 立即變色

	t := NewSerialAdaptor(port)

	const (
		SUCCESS = 0
		REBURN  = 1
		RELEASE = 2
	)

	status := func() int {
		defer t.Disconnect()

		// --- 階段 1: 燒錄 ---
		if !job.SkipBurn {
			// 執行燒錄
			if !PerformFlash(t, job.MAC, m.Meta, prefix, &job.CurrentOffset) {
				m.updateProgress(job.MAC, job.CurrentOffset, false)
				sendLog(port, "❌ 燒錄失敗 (Write Fail)")
				return RELEASE
			}

			// 🔥 FIX 2: 燒錄成功後，立刻存檔！(Checkpoint Save)
			// 這是最關鍵的一步。確保就算後面的 Verify 或重啟失敗，
			// 下一個接手的人也會看到 Offset == totalSize，進而跳過燒錄。
			m.updateProgress(job.MAC, totalSize, false)

			// 執行 Checksum 驗證與重啟
			if !VerifyChecksumAndReboot(t, m.Meta, prefix) {
				// 如果這裡失敗 (例如重啟指令沒回應)，釋放任務 (RELEASE)
				// 因為上面已經存檔了，所以下一個人會直接跳過燒錄，符合邏輯
				return RELEASE
			}

			sendProgress(port, job.MAC, 100)
			t.Disconnect()
			sendLog(port, "🛌 設備重啟，等待 15s...")
			time.Sleep(15 * time.Second)
		}

		// --- 階段 2: 驗證 ---
		connected := false
		for r := 0; r < 5; r++ {
			if err := t.Connect(job.MAC); err == nil {
				connected = true
				break
			}
			time.Sleep(2 * time.Second)
		}
		if !connected {
			sendLog(port, "⚠️ 驗證階段連線超時，釋放任務")
			return RELEASE
		}

		// 呼叫比對函式
		match, err := PerformFinalDebugCheck(t, m.Meta, prefix)

		// 🛑 情況 A: 讀取過程發生錯誤 (Timeout, I/O Error)
		// 動作: 釋放 (RELEASE)，保留進度 (因為已經存檔為 100% 了)，換人讀讀看
		if err != nil {
			sendLog(port, fmt.Sprintf("⚠️ 讀取失敗 (%v)，釋放任務給其他人", err))
			return RELEASE
		}

		// 🛑 情況 B: 讀取成功，但內容不一致
		// 動作: 重燒 (REBURN)，清空進度，原地重來
		if !match {
			sendLog(port, "⚠️ 比對不符 (內容不一致)，執行原地重燒")
			m.clearProgress(job.MAC) // 清空進度 (Offset = 0)
			return REBURN
		}

		// ✅ 情況 C: 成功
		var f uint16
		t.SendCmd(0x20, &f, []byte{0xE4, 0x00, 0x01})
		sendLog(port, "✅ 任務完成")

		// 任務完成，標記 Done = true
		m.updateProgress(job.MAC, 0, true)
		return SUCCESS
	}()

	m.MapMutex.Lock()
	if status == REBURN {
		// 重燒狀態：重置 Offset，允許燒錄，丟回佇列
		job.CurrentOffset = 0
		job.SkipBurn = false
		go func() { m.JobQueue <- job }()
		delete(m.ProcessingMap, job.MAC)
	} else if status == RELEASE {
		// 釋放狀態：從 ProcessingMap 移除，讓 GlobalScanner 可以再次掃描到它
		// 因為我們有存 Offset，所以下次被掃到時會接續進度
		delete(m.ProcessingMap, job.MAC)
		sendLog(port, "♻️ 釋放任務")
	} else if status == SUCCESS {
		// 成功狀態
		delete(m.ProcessingMap, job.MAC)
	}
	m.MapMutex.Unlock()

	m.IdlePorts <- port
}

func (m *FactoryManager) updateProgress(mac string, offset int, done bool) {
	m.MapMutex.Lock()
	defer m.MapMutex.Unlock()
	m.OffsetMap[mac] = offset
	m.DoneMap[mac] = done
}

func (m *FactoryManager) clearProgress(mac string) {
	m.MapMutex.Lock()
	defer m.MapMutex.Unlock()
	delete(m.OffsetMap, mac)
	delete(m.DoneMap, mac)
}

// --- 🔥 JSON 適配器 (讓 flash.go/debug_reader.go 也能輸出 JSON) ---

func reportLog(format string, a ...interface{}) {
	msg := fmt.Sprintf(format, a...)
	json.NewEncoder(os.Stdout).Encode(Response{Type: "LOG", Message: msg})
}

func reportProgress(mac string, pct int) {
	json.NewEncoder(os.Stdout).Encode(Response{Type: "PROGRESS", Mac: mac, Pct: pct})
}

func sendLog(port, msg string) {
	json.NewEncoder(os.Stdout).Encode(Response{Type: "LOG", Port: port, Message: msg})
}

func sendProgress(port, mac string, pct int) {
	json.NewEncoder(os.Stdout).Encode(Response{Type: "PROGRESS", Port: port, Mac: mac, Pct: pct})
}

func sendError(port, msg string) {
	json.NewEncoder(os.Stdout).Encode(Response{Type: "ERROR", Port: port, Message: msg})
}
