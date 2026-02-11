package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"go.bug.st/serial"
)

// ==========================================
// 1. 工具函式 (原 utils.go 邏輯)
// ==========================================

// addChecksum 計算從 Byte 1 開始的總和並附加於尾端
func addChecksum(data []byte) []byte {
	sum := 0
	for i := 1; i < len(data); i++ {
		sum += int(data[i])
	}
	return append(data, byte(sum&0xff))
}

// encodeAudioData 執行 +0x80 的音訊數據編碼 (Dart Protocol 關鍵邏輯)
func encodeAudioData(rawData []byte) []byte {
	var audioData []byte
	for i := 0; i < len(rawData); i++ {
		if i == 604 || i == 605 {
			// Offset 604, 605 必須填入 0xFF (Checksum 佔位符)
			audioData = append(audioData, 0xff)
		} else if i < 606 {
			// Header 區域 (0-603) 直接複製
			audioData = append(audioData, rawData[i])
		} else if i%2 == 0 {
			// 內容區域：偶數位置直接複製
			audioData = append(audioData, rawData[i])
		} else {
			// 🔥 內容區域：奇數位置必須 + 0x80
			val := int(rawData[i]) + 0x80
			audioData = append(audioData, byte(val&0xff))
		}
	}
	return audioData
}

// ==========================================
// 2. 通訊介面與實作 (原 transport.go 邏輯)
// ==========================================

type Transporter interface {
	Connect(mac string) error
	Disconnect() error
	SendCmd(target byte, fid *uint16, payload []byte) error
	SendAudioChunk(fid *uint16, offset int, data []byte) error
	ReadResponse(timeout time.Duration) ([]byte, error)
	ResetBuffer()
	WaitForACK(timeout time.Duration) error
}

type SerialAdaptor struct {
	PortName    string
	Port        serial.Port
	internalFid uint16
}

func NewSerialAdaptor(portName string) *SerialAdaptor {
	return &SerialAdaptor{PortName: portName}
}

// Connect: 回歸原始邏輯，僅增加等待時間
func (s *SerialAdaptor) Connect(mac string) error {
	mode := &serial.Mode{BaudRate: 115200}
	port, err := serial.Open(s.PortName, mode)
	if err != nil {
		return err
	}
	s.Port = port
	s.internalFid = 0

	// 1. Reset 1
	s.toggleDTR_RTS(100 * time.Millisecond)
	time.Sleep(2 * time.Second)
	s.ResetBuffer()

	// 2. Stop Scan
	s.SendCmd(0x24, nil, []byte{0x83, 0x00})
	time.Sleep(200 * time.Millisecond)

	// 3. Connect (0x85)
	cleanMac := strings.ReplaceAll(strings.TrimSpace(mac), ":", "")
	macBytes, err := hex.DecodeString(cleanMac)
	if err != nil {
		return fmt.Errorf("invalid mac: %v", err)
	}

	connPayload := []byte{0x85}
	for i := len(macBytes) - 1; i >= 0; i-- {
		connPayload = append(connPayload, macBytes[i])
	}
	s.SendCmd(0x24, nil, connPayload)

	time.Sleep(6 * time.Second)

	// 4. Reset 2 (Switch Mode)
	s.toggleDTR_RTS(100 * time.Millisecond)
	time.Sleep(1 * time.Second)

	// 5. Magic Command (0x21)
	s.SendCmd(0x21, nil, []byte{0x01})
	time.Sleep(1 * time.Second)

	return nil
}

// SendAudioChunk 保持原本邏輯
func (s *SerialAdaptor) SendAudioChunk(_ *uint16, offset int, data []byte) error {
	payload := make([]byte, 0, 1+4+2+len(data))
	payload = append(payload, 0xC5)
	payload = append(payload, byte(offset&0xff), byte((offset>>8)&0xff), byte((offset>>16)&0xff), byte((offset>>24)&0xff))
	dLen := len(data)
	payload = append(payload, byte(dLen&0xff), byte((dLen>>8)&0xff))
	payload = append(payload, data...)
	return s.SendCmd(0x20, nil, payload)
}

// SendCmd 修改：呼叫外部 addChecksum 減少重複邏輯
func (s *SerialAdaptor) SendCmd(target byte, _ *uint16, payload []byte) error {
	if s.Port == nil {
		return fmt.Errorf("port closed")
	}
	s.internalFid++
	f := s.internalFid
	plLen := len(payload)

	// 建立封包
	packet := []byte{0x25, target, byte(f & 0xff), byte((f >> 8) & 0xff), 0x00, 0x00, byte(plLen & 0xff), byte((plLen >> 8) & 0xff)}
	packet = append(packet, payload...)

	// 🔥 這裡改用整合後的函式
	packet = addChecksum(packet)

	_, err := s.Port.Write(packet)
	return err
}

func (s *SerialAdaptor) toggleDTR_RTS(sleepTime time.Duration) {
	if s.Port == nil {
		return
	}
	s.Port.SetDTR(false)
	s.Port.SetRTS(false)
	time.Sleep(sleepTime)
	s.Port.SetDTR(true)
	s.Port.SetRTS(true)
}

func (s *SerialAdaptor) Disconnect() error {
	if s.Port != nil {
		s.Port.Close()
		s.Port = nil
	}
	return nil
}

func (s *SerialAdaptor) ResetBuffer() {
	if s.Port != nil {
		s.Port.ResetInputBuffer()
		s.Port.ResetOutputBuffer()
	}
}

func (s *SerialAdaptor) WaitForACK(timeout time.Duration) error {
	if s.Port == nil {
		return fmt.Errorf("port closed")
	}
	buffer := make([]byte, 0, 256)
	temp := make([]byte, 64)
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		s.Port.SetReadTimeout(50 * time.Millisecond)
		n, _ := s.Port.Read(temp)
		if n > 0 {
			buffer = append(buffer, temp[:n]...)
			if bytes.IndexByte(buffer, 0x27) != -1 ||
				bytes.IndexByte(buffer, 0x25) != -1 ||
				bytes.IndexByte(buffer, 0x26) != -1 ||
				bytes.IndexByte(buffer, 0x23) != -1 {
				return nil
			}
			if len(buffer) > 200 {
				buffer = buffer[len(buffer)-50:]
			}
		}
	}
	return fmt.Errorf("timeout")
}

func (s *SerialAdaptor) ReadResponse(timeout time.Duration) ([]byte, error) {
	if s.Port == nil {
		return nil, fmt.Errorf("port closed")
	}
	buf := make([]byte, 4096)
	s.Port.SetReadTimeout(timeout)
	n, err := s.Port.Read(buf)
	if err != nil {
		return nil, err
	}
	return buf[:n], nil
}
