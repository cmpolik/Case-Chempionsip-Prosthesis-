const int motorPins[] = {6, 10, 11};
const int numMotors = 3;



struct MotorSettings {
  bool enabled;
  int mode;
  int T1;
  int T2;
  int numPics; // Количество пиков (дискретное значение)
  int dT;
  int currentPic;
  bool isPulsePhase;
  unsigned long phaseStartTime;
  unsigned long startTime;
  bool active;
};

int globalIntensity = 255;
int pwmFrequency = 2; // По умолчанию 976 Гц (режим 2)

// Глобальные переменные для управления последовательностью
bool isExecutingSequence = false;
unsigned long sequenceStartTime = 0;
int currentSequenceStep = 0;

MotorSettings motors[numMotors];

void setup() {
  Serial.begin(115200);
  
  // Инициализация частоты ШИМ для всех таймеров
  setPWMAllFrequency(pwmFrequency); 
  
  for (int i = 0; i < numMotors; i++) {
    pinMode(motorPins[i], OUTPUT);
    analogWrite(motorPins[i], 0);
    motors[i] = {false, 1, 2000, 100, 1, 0, 0, false, 0, 0, false};
  }
}

void handleSequenceCommand(String command) {
  // Парсинг команды и установка параметров
  parseData(command);
  
  // Запуск моторов согласно текущим настройкам
  for(int i=0; i<numMotors; i++) {
    if(motors[i].enabled) {
      motors[i].active = true;
      motors[i].startTime = millis();
      motors[i].currentPic = 0;
      motors[i].isPulsePhase = true;
      motors[i].phaseStartTime = motors[i].startTime;
    }
  }
  isExecutingSequence = true;
  sequenceStartTime = millis();
}

void checkSequenceProgress() {
  if(!isExecutingSequence) return;
  
  bool allInactive = true;
  for(int i=0; i<numMotors; i++) {
    if(motors[i].active) {
      allInactive = false;
      break;
    }
  }
  
  if(allInactive) {
    isExecutingSequence = false;
    Serial.println("STEP_COMPLETE"); // Отправляем подтверждение
  }
}


void loop() {
  if (Serial.available()) {
    String data = Serial.readStringUntil('\n');
    parseData(data);
    if(data.startsWith("SEQ:")) {
      handleSequenceCommand(data.substring(4));
    } else {
      parseData(data);
    }

    for (int i = 0; i < numMotors; i++) {
      if (motors[i].enabled) {
        motors[i].active = true;
        motors[i].startTime = millis();
        motors[i].currentPic = 0;
        motors[i].isPulsePhase = true;
        motors[i].phaseStartTime = motors[i].startTime;
      } else {
        analogWrite(motorPins[i], 0);
        motors[i].active = false;
      }
    }
  }
  updateMotors();
}

void parseData(String data) {
  int values[20];
  int index = 0;
  char buf[data.length() + 1];
  data.toCharArray(buf, sizeof(buf));
  char *token = strtok(buf, ",");
  while (token != NULL && index < 20) {
    values[index++] = atoi(token);
    token = strtok(NULL, ",");
  }

  if (index < 20) return;

  globalIntensity = map(values[0], 0, 100, 0, 255);
  pwmFrequency = values[1];
  setPWMAllFrequency(pwmFrequency);

  for (int i = 0; i < numMotors; i++) {
    int offset = 2 + i * 6;
    motors[i].enabled = (values[offset] == 1);
    motors[i].mode = values[offset + 1];
    motors[i].T1 = values[offset + 2];
    motors[i].T2 = values[offset + 3];
    motors[i].numPics = values[offset + 4]; // Дискретное значение
    motors[i].dT = values[offset + 5];
  }
}

void updateMotors() {
  unsigned long currentTime = millis();

  for (int i = 0; i < numMotors; i++) {
    if (!motors[i].active) continue;
    unsigned long elapsed = currentTime - motors[i].startTime;
    int pwm = 0;

    switch (motors[i].mode) {
      case 1: 
        if (elapsed < motors[i].T1) {
          // Квадратичное увеличение
          float t = (float)elapsed / motors[i].T1;
          pwm = (int)(globalIntensity * t * t);
        } else {
          pwm = 0;
          motors[i].active = false;
        }
        break;
      case 2: 
        if (elapsed < motors[i].T1) {
          // Квадратичное уменьшение
          float t = (float)elapsed / motors[i].T1;
          pwm = (int)(globalIntensity * (1.0 - t * t));
        } else {
          pwm = 0;
          motors[i].active = false;
        }
        break;
      case 3:
      case 4:
      case 5:
        if (motors[i].currentPic < motors[i].numPics) {
          if (motors[i].isPulsePhase) {
            unsigned long phaseElapsed = currentTime - motors[i].phaseStartTime;
            if (phaseElapsed < motors[i].T2) {
              pwm = globalIntensity;
            } else {
              if (motors[i].currentPic == motors[i].numPics - 1) {
                motors[i].currentPic = motors[i].numPics;
                pwm = 0;
                motors[i].active = false;
              } else {
                motors[i].isPulsePhase = false;
                motors[i].phaseStartTime = currentTime;
                pwm = 0;
              }
            }
          } else {
            unsigned long phaseElapsed = currentTime - motors[i].phaseStartTime;
            if (phaseElapsed < motors[i].dT) {
              pwm = 0;
            } else {
              motors[i].currentPic++;
              motors[i].isPulsePhase = true;
              motors[i].phaseStartTime = currentTime;
              pwm = globalIntensity;
            }
          }
        } else {
          pwm = 0;
          motors[i].active = false;
        }
        break;
      default:
        pwm = 0;
        motors[i].active = false;
    }

    analogWrite(motorPins[i], pwm);
  }
}

// Установка частоты ШИМ для всех таймеров
void setPWMAllFrequency(int freq) {
  // Режимы: 0-4 (частоты: 62500, 7812, 976, 488, 244 Гц)
  byte prescaler;
  switch(freq) {
    case 0: prescaler = 0x01; break; // 62500 Hz
    case 1: prescaler = 0x02; break; // 7812 Hz
    case 2: prescaler = 0x03; break; // 976 Hz (по умолчанию для таймера 0)
    case 3: prescaler = 0x04; break; // 488 Hz
    case 4: prescaler = 0x05; break; // 244 Hz
    default: prescaler = 0x03; // Default
  }

  // Настройка таймеров
  TCCR0B = (TCCR0B & 0b11111000) | prescaler; // Таймер 0 (пины 5 и 6)
  TCCR1B = (TCCR1B & 0b11111000) | prescaler; // Таймер 1 (пины 9 и 10)
  TCCR2B = (TCCR2B & 0b11111000) | prescaler; // Таймер 2 (пины 3 и 11)
}

