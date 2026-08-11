// Copiar este archivo como `credenciales.h` y poner los valores reales.
//
// credenciales.h esta en .gitignore: la clave del WiFi NO debe subirse al repositorio,
// que es publico.

#pragma once

#define WIFI_SSID      "nombre-de-tu-red"
#define WIFI_PASSWORD  "clave-de-tu-red"

// IP de la Mac que corre mosquitto, en la red local.
// Averiguarla con:  ipconfig getifaddr en0
#define MQTT_HOST      "192.168.1.100"
#define MQTT_PORT      1883
