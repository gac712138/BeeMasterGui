package main

import (
	"fmt"
	"strings"

	"go.bug.st/serial/enumerator"
)

// FindDonglePorts 掃描系統中所有的 COM Port，並過濾出 Silicon Labs 的裝置
func FindDonglePorts() []string {
	fmt.Println("🔍 正在掃描系統 COM Port...")

	// 取得詳細的 Port 列表
	ports, err := enumerator.GetDetailedPortsList()
	if err != nil {
		fmt.Printf("❌ 掃描失敗: %v\n", err)
		return []string{}
	}

	var foundPorts []string

	if len(ports) == 0 {
		fmt.Println("⚠️  未偵測到任何 COM Port")
		return foundPorts
	}

	for _, port := range ports {
		// 印出所有找到的 Port 資訊 (除錯用，之後可以註解掉)
		fmt.Printf("   Found: %s | Product: %s | VID/PID: %s\n", port.Name, port.Product, port.VID+"/"+port.PID)

		// 過濾條件：你的截圖顯示名稱包含 "Silicon Labs" 或 "CP210x"
		// 我們把它轉成大寫來比對，比較保險
		productName := strings.ToUpper(port.Product)

		// 這裡設定關鍵字，只要名稱包含這些就會被選中
		if strings.Contains(productName, "SILICON LABS") || strings.Contains(productName, "CP210X") {
			foundPorts = append(foundPorts, port.Name)
			fmt.Printf("   ✅ 識別到 Dongle: %s (%s)\n", port.Name, port.Product)
		}
	}

	fmt.Printf("📊 掃描完成，共找到 %d 個有效 Dongle\n", len(foundPorts))
	return foundPorts
}
