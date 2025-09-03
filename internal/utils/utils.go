package utils

import (
	"github.com/sirupsen/logrus"
)

var Logger *logrus.Logger

func InitLogger(level string) {
	Logger = logrus.New()
	parsedLevel, err := logrus.ParseLevel(level)
	if err != nil {
		parsedLevel = logrus.InfoLevel
	}
	Logger.SetLevel(parsedLevel)
	Logger.SetFormatter(&logrus.JSONFormatter{})
}
