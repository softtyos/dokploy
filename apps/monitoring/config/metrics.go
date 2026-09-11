package config

import (
	"encoding/json"
	"log"
	"os"
	"sync"
)

type Config struct {
	Server struct {
		ServerType    string `json:"type"`
		RefreshRate   int    `json:"refreshRate"`
		Port          int    `json:"port"`
		Token         string `json:"token"`
		UrlCallback   string `json:"urlCallback"`
		CronJob       string `json:"cronJob"`
		RetentionDays int    `json:"retentionDays"`
		Thresholds    struct {
			CPU    int `json:"cpu"`
			Memory int `json:"memory"`
		} `json:"thresholds"`
	} `json:"server"`
	Containers struct {
		RefreshRate int `json:"refreshRate"`
		Services    struct {
			Include []string `json:"include"`
			Exclude []string `json:"exclude"`
		} `json:"services"`
	} `json:"containers"`
}

var (
	config     *Config
	configOnce sync.Once
)

func GetMetricsConfig() *Config {
	configOnce.Do(func() {
		configJSON := os.Getenv("METRICS_CONFIG")
		if configJSON == "" {
			log.Fatal("METRICS_CONFIG environment variable is required")
		}

		config = &Config{}
		if err := json.Unmarshal([]byte(configJSON), config); err != nil {
			log.Fatalf("Error parsing METRICS_CONFIG: %v", err)
		}

		// Fallback defaults for missing fields
		if config.Server.Token == "" {
			config.Server.Token = "metrics"
		}
		if config.Server.Port == 0 {
			config.Server.Port = 4500
		}
		if config.Server.RefreshRate <= 0 {
			config.Server.RefreshRate = 20
		}
		if config.Server.RetentionDays <= 0 {
			config.Server.RetentionDays = 7
		}
		if config.Server.CronJob == "" {
			config.Server.CronJob = "0 0 * * *"
		}
		if config.Containers.RefreshRate <= 0 {
			config.Containers.RefreshRate = 20
		}
		if config.Server.UrlCallback == "" {
			log.Println("Warning: urlCallback is not configured. Webhook notifications will be skipped.")
		}
	})

	return config
}
