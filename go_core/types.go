package main

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
