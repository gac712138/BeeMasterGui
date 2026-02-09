package main

import (
	"fmt"
	"time"
)

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
