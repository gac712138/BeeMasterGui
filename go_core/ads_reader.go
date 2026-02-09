package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"text/tabwriter"
)

func ParseADSFile(path string) FileMeta {
	fmt.Printf("🕵️‍♂️ 正在解析本地檔案: %s\n", path)
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Printf("❌ 無法開啟: %v\n", err)
		return FileMeta{}
	}
	magicCode := []byte{0x27, 0x9D}
	headerIdx := bytes.Index(data, magicCode)
	if headerIdx == -1 {
		fmt.Printf("❌ 找不到 Magic Code\n")
		return FileMeta{}
	}
	_, tracks := parseHeaderBytes(data[headerIdx:headerIdx+606], "Local ADS", "[FILE]")

	// 🔥 關鍵修正：呼叫 utils.go 中的 encodeAudioData 進行轉碼
	fmt.Println("🎼 正在執行音訊編碼轉換 (+0x80)...")
	encoded := encodeAudioData(data)

	return FileMeta{
		RawData:     data,
		EncodedData: encoded, // ✅ 現在這裡是編碼過的正確資料
		SizeKB:      len(data) / 1024,
		Tracks:      tracks,
	}
}

func parseHeaderBytes(data []byte, label string, prefix string) (int, map[int]TrackInfo) {
	trackCount := int(data[2])
	fmt.Printf("%s 📊 [%s] 軌道數量: %d\n", prefix, label, trackCount)

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintf(w, "%s No.\tTrack ID\tSize (Bytes)\n", prefix)

	tracks := make(map[int]TrackInfo)
	baseOffset := 4
	for i := 0; i < trackCount; i++ {
		if i >= 50 {
			break
		}
		off := baseOffset + (i * 12)
		info := TrackInfo{
			ID:     binary.LittleEndian.Uint32(data[off : off+4]),
			Offset: binary.LittleEndian.Uint32(data[off+4 : off+8]),
			Size:   binary.LittleEndian.Uint32(data[off+8 : off+12]),
		}
		tracks[i+1] = info
		fmt.Fprintf(w, "%s %d\t%d\t%d\n", prefix, i+1, info.ID, info.Size)
	}
	w.Flush()
	return trackCount, tracks
}
