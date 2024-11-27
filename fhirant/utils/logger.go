package utils

import (
	"log"
	"os"
)

// InitLogger configures the logger with a standard format.
func InitLogger() {
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.SetOutput(os.Stdout)
	log.Println("Logger initialized.")
}
