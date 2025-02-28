import controlP5.*;
import processing.serial.Serial;
import java.io.*;

ControlP5 cp5;
processing.serial.Serial myPort;

PFont font;
int intensity = 100;
int pwmFrequency = 2; // Индекс частоты (0-4)
boolean[] motorEnabled = {false, false, false};
int[] motorMode = {1, 1, 1};
int[] T1 = {2000, 2000, 2000};
int[] T2 = {100, 100, 100};
int[] numPics = {1, 1, 1}; // Дискретное значение
int[] dT = {0, 0, 0};

boolean runPressed = false;
long commandCompleteTime = 0;

// Переменные для воспроизведения
ArrayList<String> commandQueue = new ArrayList<>();
int currentCommandIndex = 0;
boolean isPlaying = false;
int delayBetweenCommands = 1000; // Задержка по умолчанию 1 секунда
long lastCommandTime = 0;

void setup() {
  size(800, 600);
  cp5 = new ControlP5(this);
  font = createFont("Arial", 16);
  textFont(font);
  
  background(50);
  
  cp5.addSlider("intensity")
     .setPosition(20, 40)
     .setSize(200, 30)
     .setRange(0, 100)
     .setLabel("Intensity Factor")
     .setColorLabel(color(255));

  // Выбор частоты PWM
  cp5.addScrollableList("pwmFrequency")
     .setPosition(250, 40)
     .setSize(200, 100)
     .addItems(new String[]{"62500 Hz", "7812 Hz", "976 Hz", "488 Hz", "244 Hz"})
     .setLabel("PWM Frequency")
     .setColorLabel(color(255));

  for (int i = 0; i < 3; i++) {
    int yOffset = 100 + i * 160;
    
    cp5.addToggle("motor" + i)
       .setPosition(20, yOffset)
       .setSize(60, 30)
       .setLabel("Motor " + (i + 1))
       .setColorLabel(color(255));

    cp5.addScrollableList("mode" + i)
       .setPosition(90, yOffset)
       .setSize(150, 100)
       .addItems(new String[]{"Increase", "Decrease", "Low Pic", "Mid Pic", "High Pic"})
       .setColorLabel(color(255));

    cp5.addSlider("T1_" + i)
       .setPosition(250, yOffset)
       .setSize(120, 20)
       .setRange(100, 2000)
       .setValue(2000)
       .setLabel("T1 (ms)")
       .setColorLabel(color(255));

    cp5.addSlider("T2_" + i)
       .setPosition(380, yOffset)
       .setSize(120, 20)
       .setRange(50, 500)
       .setLabel("T2 (ms)")
       .setColorLabel(color(255));

    cp5.addSlider("numPics_" + i)
       .setPosition(250, yOffset + 40)
       .setSize(120, 20)
       .setRange(1, 10)
       .setValue(1)
       .setLabel("Num Pics")
       .setColorLabel(color(255));

    cp5.addSlider("dT_" + i)
       .setPosition(380, yOffset + 40)
       .setSize(120, 20)
       .setRange(0, 1000)
       .setLabel("dT (ms)")
       .setColorLabel(color(255));
  }

  cp5.addButton("RUN")
     .setPosition(300, 540)
     .setSize(100, 40)
     .setLabel("RUN")
     .setColorLabel(color(255));

  cp5.addButton("SAVE")
     .setPosition(420, 540)
     .setSize(100, 40)
     .setLabel("SAVE")
     .setColorLabel(color(255));

  cp5.addTextfield("delayInput")
     .setPosition(20, 540)
     .setSize(80, 30)
     .setLabel("Delay (ms)")
     .setColorLabel(color(255))
     .setText(str(delayBetweenCommands));
     
  cp5.addButton("LOAD")
     .setPosition(540, 540)
     .setSize(100, 40)
     .setLabel("LOAD")
     .setColorLabel(color(255));
     
  cp5.addButton("PLAY")
     .setPosition(650, 540)
     .setSize(100, 40)
     .setLabel("PLAY/STOP")
     .setColorLabel(color(255));
  
  String portName = Serial.list()[0];
  myPort = new Serial(this, portName, 115200);
  myPort.bufferUntil('\n'); // Важно для корректного чтения строк
}

void draw() {
  background(50);
  fill(255);
  textSize(20);
  text("Vibration Motor Control Panel", 20, 30);
  
  if(isPlaying && millis() - lastCommandTime > delayBetweenCommands) {
    if(currentCommandIndex < commandQueue.size()) {
      String command = commandQueue.get(currentCommandIndex);
      myPort.write(command + "\n");
      println("Executing command: " + command);
      currentCommandIndex++;
      lastCommandTime = millis();
    } else {
      isPlaying = false;
      println("Playback finished");
    }
  }
}


void LOAD() {
  loadCommandsFromFile();
}

void PLAY() {
  if(commandQueue.size() > 0) {
    isPlaying = !isPlaying;
    if(isPlaying && currentCommandIndex >= commandQueue.size()) {
      currentCommandIndex = 0;
    }
  }
}

void RUN() {
  sendToArduino();
}

void SAVE() {
  saveSettings();
}

void saveSettings() {
  try {
    // Открываем файл в режиме добавления (append)
    FileWriter fw = new FileWriter(sketchPath("motor_settings.txt"), true);
    PrintWriter output = new PrintWriter(fw);
    
    // Формируем строку с данными, аналогично команде для Arduino
    String data = intensity + "," + pwmFrequency;
    for (int i = 0; i < 3; i++) {
      data += "," + (motorEnabled[i] ? "1" : "0");
      data += "," + motorMode[i];
      data += "," + T1[i];
      data += "," + T2[i];
      data += "," + numPics[i];
      data += "," + dT[i];
    }
    
    output.println(data); // Записываем строку в файл
    output.close();
  } catch (IOException e) {
    e.printStackTrace();
  }
  println("Settings saved to motor_settings.txt");
}


void controlEvent(ControlEvent event) {
  String name = event.getName();
  if (name.equals("intensity")) {
    intensity = (int) event.getValue();
  } else if (name.equals("pwmFrequency")) {
    pwmFrequency = (int) event.getValue();
  }
  for (int i = 0; i < 3; i++) {
    if (name.equals("motor" + i)) {
      motorEnabled[i] = event.getValue() == 1;
    } else if (name.equals("mode" + i)) {
      motorMode[i] = (int) event.getValue() + 1;
    } else if (name.equals("T1_" + i)) {
      T1[i] = (int) event.getValue();
    } else if (name.equals("T2_" + i)) {
      T2[i] = (int) event.getValue();
    } else if (name.equals("numPics_" + i)) {
      numPics[i] = (int) event.getValue();
    } else if (name.equals("dT_" + i)) {
      dT[i] = (int) event.getValue();
    }
  }
  if(event.getName().equals("delayInput")) {
    delayBetweenCommands = Integer.parseInt(event.getStringValue());
  }
}

void loadCommandsFromFile() {
  commandQueue.clear();
  try {
    BufferedReader reader = createReader("motor_settings.txt");
    String line;
    while((line = reader.readLine()) != null) {
      commandQueue.add(line);
    }
    reader.close();
    println("Loaded " + commandQueue.size() + " commands");
  } catch(Exception e) {
    println("Error loading commands: " + e.getMessage());
  }
}

void sendToArduino() {
  String command = str(intensity) + "," + str(pwmFrequency);
  for (int i = 0; i < 3; i++) {
    command += "," + (motorEnabled[i] ? "1" : "0");
    command += "," + motorMode[i];
    command += "," + T1[i];
    command += "," + T2[i];
    command += "," + numPics[i];
    command += "," + dT[i];
  }
  println("Sending: " + command);
  myPort.write(command + "\n");
}
