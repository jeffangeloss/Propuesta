/*
 * Nodo de captura biométrica — implementación.
 * Ver nodo.h para por qué el código no vive en el .ino.
 */

#include <Arduino.h>
#include "nodo.h"
#include <WiFi.h>
#include <Wire.h>
#include <PubSubClient.h>
#include "credenciales.h"

// ---------------------------------------------------------------- pines
static const int PIN_SDA = 21;
static const int PIN_SCL = 22;
static const int PIN_LED = 2;

// ---------------------------------------------------------------- muestreo
static const uint32_t HZ           = 50;
static const uint32_t PERIODO_US   = 1000000UL / HZ;   // 20 000 us
static const int      TAM_LOTE     = 10;               // -> 5 mensajes por segundo

// ---------------------------------------------------------------- MPU-6050
static const uint8_t MPU_ADDR      = 0x68;  // 0x69 si AD0 va a 3.3V
static const uint8_t REG_PWR_MGMT1 = 0x6B;
static const uint8_t REG_CONFIG    = 0x1A;
static const uint8_t REG_ACCEL_CFG = 0x1C;
static const uint8_t REG_ACCEL_XH  = 0x3B;

// Rango ±8 g. Un golpe seco supera fácilmente los 2 g y con el rango por defecto se
// recortaría justo en el pico, que es exactamente lo que hay que medir.
static const uint8_t ACCEL_CFG     = 0x10;
static const float   LSB_POR_G     = 4096.0f;

WiFiClient red;
PubSubClient mqtt(red);

static float loteAx[TAM_LOTE], loteAy[TAM_LOTE], loteAz[TAM_LOTE];
static int      n        = 0;
static uint32_t seq      = 0;
static uint32_t tLote    = 0;      // micros() de la primera muestra del lote
static uint32_t tSiguiente = 0;
static char     carga[1024];

// ---------------------------------------------------------------- MPU

static bool escribirReg(uint8_t reg, uint8_t valor) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(valor);
  return Wire.endTransmission() == 0;
}

static bool iniciarMPU() {
  Wire.begin(PIN_SDA, PIN_SCL, 400000);
  delay(100);
  if (!escribirReg(REG_PWR_MGMT1, 0x00)) return false;   // despertar
  delay(50);
  // DLPF en 0: ancho de banda ~260 Hz. Un filtro más agresivo suavizaría los golpes,
  // que es justo la señal que interesa conservar.
  escribirReg(REG_CONFIG, 0x00);
  escribirReg(REG_ACCEL_CFG, ACCEL_CFG);
  delay(50);
  return true;
}

static bool leerAcel(float &ax, float &ay, float &az) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(REG_ACCEL_XH);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((int)MPU_ADDR, 6, (int)true) != 6) return false;

  int16_t x = (Wire.read() << 8) | Wire.read();
  int16_t y = (Wire.read() << 8) | Wire.read();
  int16_t z = (Wire.read() << 8) | Wire.read();

  ax = x / LSB_POR_G;
  ay = y / LSB_POR_G;
  az = z / LSB_POR_G;
  return true;
}

// ---------------------------------------------------------------- red

static void parpadear(int ms) {
  digitalWrite(PIN_LED, !digitalRead(PIN_LED));
  delay(ms);
}

static void conectarWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  Serial.printf("WiFi -> %s ", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);   // el ahorro de energía mete latencia variable en la publicación
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    parpadear(120);
    Serial.print(".");
  }
  Serial.printf(" ok, ip %s\n", WiFi.localIP().toString().c_str());
}

static void conectarMQTT() {
  while (!mqtt.connected()) {
    Serial.printf("MQTT -> %s:%d ", MQTT_HOST, MQTT_PORT);
    char id[32];
    snprintf(id, sizeof(id), "esp32-bio-%06X", (uint32_t)(ESP.getEfuseMac() & 0xFFFFFF));
    if (mqtt.connect(id)) {
      Serial.println("ok");
      digitalWrite(PIN_LED, HIGH);
    } else {
      Serial.printf("fallo rc=%d, reintento\n", mqtt.state());
      for (int i = 0; i < 10; i++) parpadear(100);
    }
  }
}

// ---------------------------------------------------------------- lote

static void publicarLote() {
  int p = snprintf(carga, sizeof(carga),
                   "{\"seq\":%lu,\"t_us\":%lu,\"dt_us\":%lu,\"ax\":[",
                   (unsigned long)seq, (unsigned long)tLote, (unsigned long)PERIODO_US);

  const char *nombres[3] = {"ay", "az", nullptr};
  const float *series[3] = {loteAx, loteAy, loteAz};

  for (int s = 0; s < 3; s++) {
    for (int i = 0; i < n; i++) {
      p += snprintf(carga + p, sizeof(carga) - p, "%s%.4f", i ? "," : "", series[s][i]);
    }
    if (s < 2) p += snprintf(carga + p, sizeof(carga) - p, "],\"%s\":[", nombres[s]);
  }
  p += snprintf(carga + p, sizeof(carga) - p, "]}");

  if (!mqtt.publish("tesis/bio/imu", carga)) {
    // El seq NO se retrocede: el suscriptor debe ver el hueco.
    Serial.println("[!] fallo al publicar");
    digitalWrite(PIN_LED, LOW);
  }
  n = 0;
}

// ---------------------------------------------------------------- ciclo

void nodoSetup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);
  delay(300);
  Serial.println("\n=== nodo biometrico — tesis ===");

  if (!iniciarMPU()) {
    Serial.println("[!] no responde el MPU-6050. Revisar cableado y direccion I2C (0x68/0x69).");
    while (true) parpadear(500);
  }
  Serial.printf("MPU-6050 ok, rango +-8g, %lu Hz, lotes de %d\n", (unsigned long)HZ, TAM_LOTE);

  conectarWiFi();
  // El buffer por defecto de PubSubClient es de 256 bytes: un lote de 10 muestras no cabe
  // y publish() falla en silencio devolviendo false.
  mqtt.setBufferSize(1024);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  conectarMQTT();

  tSiguiente = micros();
}

void nodoLoop() {
  if (WiFi.status() != WL_CONNECTED) { digitalWrite(PIN_LED, LOW); conectarWiFi(); }
  if (!mqtt.connected())             { digitalWrite(PIN_LED, LOW); conectarMQTT(); }
  mqtt.loop();

  uint32_t ahora = micros();
  if ((int32_t)(ahora - tSiguiente) < 0) return;
  tSiguiente += PERIODO_US;

  // Si se acumuló retraso (reconexión, por ejemplo), se resincroniza en vez de
  // disparar una ráfaga de muestras con marcas de tiempo falsas.
  if ((int32_t)(micros() - tSiguiente) > (int32_t)(PERIODO_US * 5)) tSiguiente = micros() + PERIODO_US;

  float ax, ay, az;
  if (!leerAcel(ax, ay, az)) {
    Serial.println("[!] lectura I2C fallida");
    return;
  }

  if (n == 0) tLote = ahora;
  loteAx[n] = ax; loteAy[n] = ay; loteAz[n] = az;
  n++;

  if (n >= TAM_LOTE) {
    seq++;
    publicarLote();
    digitalWrite(PIN_LED, HIGH);
  }
}
