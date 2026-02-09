package main

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
