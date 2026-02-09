package main

import (
	"bytes"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"go.bug.st/serial"
)

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

	// 🔥 唯一的修正：將原本的 4秒 改為 6秒
	// 有些設備在藍牙連線時需要更長時間握手，多等這 2 秒可以大幅降低解鎖失敗率
	time.Sleep(6 * time.Second)

	// 4. Reset 2 (Switch Mode)
	s.toggleDTR_RTS(100 * time.Millisecond)

	// 🔥 這裡也稍微加長一點，確保 Mode 切換完成
	time.Sleep(1 * time.Second)

	// 5. Magic Command (0x21)
	// 回歸原始：只發送不檢查 ACK (盲發)
	// 這樣可以避免因為讀取緩衝區問題導致的誤判
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

func (s *SerialAdaptor) SendCmd(target byte, _ *uint16, payload []byte) error {
	if s.Port == nil {
		return fmt.Errorf("port closed")
	}
	s.internalFid++
	f := s.internalFid
	plLen := len(payload)
	packet := []byte{0x25, target, byte(f & 0xff), byte((f >> 8) & 0xff), 0x00, 0x00, byte(plLen & 0xff), byte((plLen >> 8) & 0xff)}
	packet = append(packet, payload...)
	sum := 0
	for i := 1; i < len(packet); i++ {
		sum += int(packet[i])
	}
	packet = append(packet, byte(sum&0xff))
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

// WaitForACK: 保持您原本的寬鬆檢查邏輯
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
