#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>
#include <Adafruit_BMP085.h>
#include <avr/interrupt.h>

// #define DEBUG_NO_BREATH
#define DO_SYNTH true
// #define DEBUG_SERIAL

#ifdef DEBUG_SERIAL
  #include <SoftwareSerial.h>
  SoftwareSerial debugSerial (10, 11);
#endif

#define TUNING 2.125
#define PITCH_BEND_MULTIPLIER 1
// #define PRESSURE_MULTIPLIER .5
#define PRESSURE_MULTIPLIER 1

#define N_SERVOS 6
const int SERVO_PINS[N_SERVOS] = {10,11,12,13,14,15};
#define N_CAPAS 12
const int CAPACITIVE_PINS[N_CAPAS] = {
  7,6,5,4,3,2,10,11,12,A0,A1,A2
};
volatile uint8_t** P_OUT = new volatile uint8_t*[N_CAPAS];
volatile uint8_t** DDR   = new volatile uint8_t*[N_CAPAS];
volatile uint8_t** P_IN  = new volatile uint8_t*[N_CAPAS];
byte BITMASK[N_CAPAS] = { 0 };
#define PEDAL_PIN 12
#define SYNTH_PIN 9
#define INIT_MID 95
#define DEFAULT_CAPACITIVE_THRESHOLD 4

#define MINPULSE 150 // This is the 'minimum' pulse length count (out of 4096)
#define MAXPULSE 600 // This is the 'maximum' pulse length count (out of 4096)
#define SERVO_FREQ 50 // Analog servos run at ~50 Hz updates
#define OSC_FREQ 24890000 // Specific to each PCA 9685 board

#define ROUND_ROBIN_PACKET_MAX_SIZE 127 // one-byte length indicator maximum 127 on serial

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver();
Adafruit_BMP085 bmp;
bool _abort = false;

// For detach
int detach_slow = 5;
int last_degree[N_SERVOS] = {0};
int detach_target_degree[N_SERVOS] = {0};
int last_detach_millis;

uint8_t capacitive_threshold = DEFAULT_CAPACITIVE_THRESHOLD;
#define ATMOS_OFFSET 36000
int atmos_pressure = -1;
int measure_atmos_state = 20;
long measure_atmos_tmp = 0;
int measure_atmos_times = 0;

// For Serial communication
#define BUFF_LEN_S 4
#define BUFF_LEN_D 5
#define BUFF_LEN_C 1
#define BUFF_LEN_P 2
#define BUFF_LEN_Y 2
#define BUFF_LEN_M 4
#define BUFF_LEN_A 2
#define BUFF_LEN_R 6
#define BUFF_LEN_W 1
#define LONGEST_COMMAND 6  // max(BUFF_LEN_ S D R)
char command_buffer[LONGEST_COMMAND] = {' '};
char header = NULL;
int n_char_expect;
int n_char_got;
bool hand_shaked = false;

bool last_capa[N_CAPAS] = {false};

// For pedal diffing
bool last_pedal = false;

// For synthesis
volatile short phase_per_sample = 0;  // 0 - 1, not 0 - 2pi
volatile byte amplitude = 0;   // 0 - 255
bool proc_override_synth = false;

#define MIDI_BUF_SIZE 64
byte midi_buf_pop_i  = 0;
byte midi_buf_push_i = 0;
byte  midi_buf_pitch[MIDI_BUF_SIZE] = {0};
short midi_buf_dt   [MIDI_BUF_SIZE] = {0};
unsigned long sync_clock_zero = 0;

// network "HHF"
//#define PARA_EXPONENT 3.5
#define PARA_EXPONENT 3.4
#define ON_THRESHOLD 25000
#define OFF_THRESHOLD 18000
#define PARA_OT_SLOPE 0.53
// #define PARA_OT_INTERCEPT -11.514012809196554
#define PARA_OT_INTERCEPT -13
#define PARA_OT_HYSTERESIS 0.6959966494737573
#define PARA_PB_SLOPE 0.1
// #define PARA_PB_SLOPE 0.16562851414401
// #define PARA_PB_SLOPE 0.3
float ONE_OVER_PARA_OT_SLOPE = 1. / PARA_OT_SLOPE;
float PARA_OT_INTERCEPT_PLUS_HALF_HYST = (
  PARA_OT_INTERCEPT + PARA_OT_HYSTERESIS / 2
);
bool need_note_event = false;
bool finger_changed = false;

#define HUHUHU_SMOOTH_GAIN .2
float HUHUHU_SMOOTH_KEEP = 1. - HUHUHU_SMOOTH_GAIN;
float HUHUHU_SMOOTH_TIME = 1. / HUHUHU_SMOOTH_GAIN - 1.;
#define HUHUHU_THRESHOLD 4
#define HUHUHU_RESET_THRESHOLD -0.1
float huhuhu_smooth_velocity = 0.;
float huhuhu_smooth_dt = 0.;
long huhuhu_last_millis = 0;
bool huhuhu_ready = false;

#define AUTO_MODE_NONE 0
#define AUTO_MODE_PITCH 1
#define AUTO_MODE_OCTAVE 2
uint8_t auto_po_mode = AUTO_MODE_NONE; 
// AUTO_MODE_NONE | ...PITCH | ...OCTAVE
uint8_t auto_po_next;
#define AUTO_PO_COMMIT_TIME 200
long auto_po_commit_when;

void setup() {
  #ifdef DEBUG_SERIAL
    debugSerial.begin(9600);
    debugSerial.write("debugSerial is ready. \n");
  #endif
  pwm.begin();
  pwm.setOscillatorFrequency(OSC_FREQ);
  pwm.setPWMFreq(SERVO_FREQ);

  for (int i = 0; i < N_SERVOS; i++) {
    setServo(i, INIT_MID);
    last_degree[i] = INIT_MID; // in case you relax() before sending any attach command
  }

  if (DO_SYNTH) {
    /******** Set timer1 for 8-bit fast PWM output ********/
    pinMode(SYNTH_PIN, OUTPUT); // Make timer's PWM pin an output
    TCCR1B  = (1 << CS10);      // Set prescaler to full 16MHz
    TCCR1A |= (1 << COM1A1);    // PWM pin to go low when TCNT1=OCR1A
    TCCR1A |= (1 << WGM10);     // Put timer into 8-bit fast PWM mode
    TCCR1B |= (1 << WGM12); 

    /******** Set up timer 2 to call ISR ********/
    TCCR2A = 0;               // We need no options in control register A
    TCCR2B = (1 << CS21);     // Set prescaller to divide by 8
    TIMSK2 = (1 << OCIE2A);   // Set timer to call ISR when TCNT2 = OCRA2
    OCR2A = 64;               // sets the frequency of the generated wave
    sei();                    // Enable interrupts to generate waveform!
  }

  pinMode(PEDAL_PIN, INPUT);
  Serial.begin(9600);
  handShake();
  
  cacheCapaPins();
  last_detach_millis = millis();
  #ifndef DEBUG_NO_BREATH
    if (! bmp.begin()) {
      fatalError("Could not find a valid BMP085 sensor, check wiring!");
      return;
    }
  #endif
}

void handShake() {
  String expecting = "hi arduino";
  int len = expecting.length();
  for (int i = 0; i < len; i++) {
    if (readOne() != expecting[i]) {
      _abort = true;
      fatalError("Handshake failed! ");
      return;
    }
  }
  Serial.print("hi processing");
  hand_shaked = true;
}

char readOne() {    // blocking
  int recved = -1;
  while (recved == -1) {
    recved = Serial.read();
  }
  return (char) recved;
}

void loop() {
  if (_abort) {
    roundRobin_loop();
    return;
  }
  roundRobin_loop();
  roundRobin_loop();  // twice
  handleDetach();
  if (roundRobin_available() > 0) {
    mySerialEvent();
  }
  relayCapacitive();
  // relayPedal();
  getPressure();
  handleSynth();
}

void mySerialEvent() {
  if (! hand_shaked) return;
  char recved;
  while (roundRobin_available()) {
    recved = roundRobin_read();
    if (header == NULL) {
      header = recved;
      n_char_got = 0;
      if (header == '\r') {
        n_char_expect = BUFF_LEN_R;
      } else if (header == 'S') {
        n_char_expect = BUFF_LEN_S;
      } else if (header == 'D') {
        n_char_expect = BUFF_LEN_D;
      } else if (header == 'C') {
        n_char_expect = BUFF_LEN_C;
      } else if (header == 'P') {
        n_char_expect = BUFF_LEN_P;
      } else if (header == 'Y') {
        n_char_expect = BUFF_LEN_Y;
      } else if (header == 'M') {
        n_char_expect = BUFF_LEN_M;
      } else if (header == 'A') {
        n_char_expect = BUFF_LEN_A;
      } else if (header == 'W') {
        n_char_expect = BUFF_LEN_W;
      } else {
        fatalError("Unknown header: chr(" + String(int(header)) + ')');
        return;
      }
    } else {
      command_buffer[n_char_got] = recved;
      n_char_got ++;
      if (n_char_got == n_char_expect) {
        handleCommand();
        header = NULL;
      }
    }
  }
}

void handleCommand() {
  if (header == '\r') {
    String str_command = String(command_buffer).substring(0, 6);  // Stupid \x00 problem
    if (str_command.equals("ABORT_")) {
      _abort = true;
      return;
    } else {
      fatalError("Unknown command starting with \\r: ");
      roundRobin_println(str_command);
      return;
    }
  } else if (header == 'S' || header == 'D') {
    int servo_ID = int(command_buffer[1]) - int('2');
    if (command_buffer[0] == 'R') {
      servo_ID += 3;
    }
    if (servo_ID >= N_SERVOS || servo_ID < 0) {
      fatalError("Invalid servo ID: ");
      roundRobin_write(command_buffer[0]);
      roundRobin_write(command_buffer[1]);
      return;
    }
    int degree = decodeDegree(command_buffer[2], command_buffer[3]);
    if (isDegreeIllegal(degree)) {
      return;
    }
    if (header == 'S') {
      attach(servo_ID, degree);
    } else if (header == 'D') {
      detach_slow = decodeDigit(command_buffer[4]);
      detach(servo_ID, degree);
    }
  } else if (header == 'C') {
    capacitive_threshold = (uint8_t) command_buffer[0];
  } else if (header == 'P') {
    measure_atmos_tmp = 0;
    measure_atmos_times = 0;
    measure_atmos_state = decodeDegree(command_buffer[0], command_buffer[1]);
  } else if (header == 'Y') {
    sync_clock_zero = millis() + decodeDegree(
      command_buffer[0], command_buffer[1]
    );
    midi_buf_push_i = midi_buf_pop_i;
  } else if (header == 'M') {
    proc_override_synth = true;
    midi_buf_pitch[midi_buf_push_i] = decodeDegree(
      command_buffer[0], command_buffer[1]
    );
    midi_buf_dt   [midi_buf_push_i] = decodeDegree(
      command_buffer[2], command_buffer[3]
    );
    if (midi_buf_push_i == midi_buf_pop_i) {
      // from empty to 1
      short loss = millis() - sync_clock_zero - midi_buf_dt[
        midi_buf_pop_i
      ];
      if (loss >= 0) {
        sendDebugSentence("buf loss " + String(loss) + " ms");
        // sendDebugSentence("dt " + String(midi_buf_dt   [midi_buf_pop_i]));
        // sendDebugSentence("c " + String(sync_clock_zero));
      }
    }
    midi_buf_push_i = (midi_buf_push_i + 1) % MIDI_BUF_SIZE;
    if (midi_buf_push_i == midi_buf_pop_i) {
      // Ill defined state. Cannot tell if buf is full or empty. 
      fatalError("MIDI buf overflow.");
      return;
    }
  } else if (header == 'A') {
    auto_po_mode = command_buffer[0] - 1;
    auto_po_next = command_buffer[1];
  } else if (header == 'W') {
    workOut();
  }
}

bool isDegreeIllegal(int degree) {
  if (degree > 180 || degree < 0) {
    fatalError("Invalid degree: ");
    roundRobin_println(String(degree));
    return true;
  }
  return false;
}

void fatalError(String msg) {
  roundRobin_println("ERRArduino fatal Error: " + msg);
  _abort = true;
}

int decodeDigit(char x) {
  return (int) x - (int) '0';
}

int decodeDegree(char a, char b) {
  return 127 * (((int) a) - 1) + ((int) b) - 1;
}

void detach(int servo_ID, int degree) {
  detach_target_degree[servo_ID] = degree;
}

void attach(int servo_ID, int degree) {
  setServo(servo_ID, degree);
  last_degree[servo_ID] = degree;
  detach_target_degree[servo_ID] = NULL;
}

void handleDetach() {
  while ((millis() + 1000 - last_detach_millis) % 1000 >= detach_slow) {
    last_detach_millis += detach_slow;
    last_detach_millis %= 1000;
    for (int i = 0; i < N_SERVOS; i++) {
      if (detach_target_degree[i] != NULL) {
        if (detach_target_degree[i] > last_degree[i]) {
          last_degree[i] ++;
        } else {
          last_degree[i] --;
        }
        setServo(i, last_degree[i]);
        if (last_degree[i] == detach_target_degree[i]) {
          detach_target_degree[i] = NULL;
        }
      }
    }
  }
}

void cacheCapaPins() {
  for (int i = 0; i < N_CAPAS; i ++) {
    P_OUT  [i] = portOutputRegister(digitalPinToPort(CAPACITIVE_PINS[i]));
    P_IN   [i] = portInputRegister(digitalPinToPort(CAPACITIVE_PINS[i]));
    DDR    [i] = portModeRegister(digitalPinToPort(CAPACITIVE_PINS[i]));
    BITMASK[i] = digitalPinToBitMask(CAPACITIVE_PINS[i]);
  }
}

uint8_t readCapacitive(int capa_i) {
  volatile uint8_t* p_out = P_OUT[capa_i];
  volatile uint8_t* p_in  = P_IN [capa_i];
  volatile uint8_t* ddr   = DDR  [capa_i];
  byte bitmask = BITMASK[capa_i];
  uint8_t SREG_old = SREG; // back up the AVR Status Register
  uint8_t cycles = 8;
  delay(1);     // Improves readings, no idea why!!!
  noInterrupts();   // disable interrupts
  *ddr &= ~ bitmask;    // mode: in
  *p_out |= bitmask;    // write HIGH
  if (*p_in & bitmask) {
    cycles =  0;
  } else if (*p_in & bitmask) {
    cycles =  1;
  } else if (*p_in & bitmask) {
    cycles =  2;
  } else if (*p_in & bitmask) {
    cycles =  3;
  } else if (*p_in & bitmask) {
    cycles =  4;
  } else if (*p_in & bitmask) {
    cycles =  5;
  } else if (*p_in & bitmask) {
    cycles =  6;
  } else if (*p_in & bitmask) {
    cycles =  7;
  }
  interrupts();   // enable interrupts
  SREG = SREG_old;
  *p_out &= ~ bitmask;  // write LOW
  *ddr |= bitmask;      // mode: out
  return cycles;
}

void relayCapacitive() {
  for (int i = 0; i < N_SERVOS; i ++) {
    uint8_t reading = readCapacitive(i);
    bool in_contact = reading >= capacitive_threshold;
    if (in_contact != last_capa[i]) {
      last_capa[i] = in_contact;
      onFingerChange();
      roundRobin_write('F');
      roundRobin_write((char) ((int)'0' + i));
      if (in_contact) {
        roundRobin_write('_');
      } else {
        roundRobin_write('^');
      }
      // proc first knows the fingers, then the note event. 
      checkNoteEvent();
    }
  }
}

void relayPedal() {
  bool now_pedal = digitalRead(PEDAL_PIN);
  if (now_pedal != last_pedal) {
    last_pedal = now_pedal;
    roundRobin_write('P');
    if (now_pedal) {
      roundRobin_write('_');
    } else {
      roundRobin_write('^');
    }
    roundRobin_write(';');
  }
}

void setServo(int id, int angle) {
  pwm.setPWM(SERVO_PINS[id], 0, map(angle, 0, 180, MINPULSE, MAXPULSE));
}

void sendDebugMsg(String msg) {
  roundRobin_write('D');
  roundRobin_print(msg.substring(0, 2));
}

void sendDebugSentence(String msg) {
  msg = "\n" + msg;
  if (msg.length() % 2 == 0) {
    msg += " \n";
  } else {
    msg += "\n";
  }
  for (int i = 0; i < msg.length(); i += 2) {
    sendDebugMsg(msg.substring(i, i + 2));
  }
}

// Round Robin
String round_robin_in_queue = "";
String round_robin_out_queue = "";
int round_robin_my_turn = false;
int round_robin_recv_state = -1;

void sendDebugSentenceNow(String msg) {
  sendDebugSentence(msg);
  while (! round_robin_my_turn) {
    roundRobin_loop();
  }
  roundRobin_loop();
}

void roundRobin_loop() {
  if (round_robin_my_turn) {
    int packet_size = min(round_robin_out_queue.length(), ROUND_ROBIN_PACKET_MAX_SIZE);
    Serial.write((char) packet_size);
    if (packet_size > 0) {
      Serial.print(round_robin_out_queue.substring(0, packet_size));
      round_robin_out_queue = round_robin_out_queue.substring(packet_size);
    }
    round_robin_my_turn = false;
    round_robin_recv_state = -1;
  } else {
    while (Serial.available() > 0) {
      if (round_robin_recv_state == -1) {
        round_robin_recv_state = Serial.read();
      } else {
        // rr_state > 0
        round_robin_in_queue += (char) Serial.read();
        // This leads to memory fragmentation quickly. 
        // Too bad.
        round_robin_recv_state -= 1;
      }
      if (round_robin_recv_state == 0) {
        round_robin_my_turn = true;
        Serial.write('\n');
        break;
      }
    }
  }  
}

int roundRobin_available() {
  return round_robin_in_queue.length();
}

char roundRobin_read() {
  char tmp = round_robin_in_queue.charAt(0);
  round_robin_in_queue = round_robin_in_queue.substring(1);
  return tmp;
}

void roundRobin_write(char x) {
  round_robin_out_queue += x;
}

void roundRobin_print(String x) {
  round_robin_out_queue += x;
}

void roundRobin_println(String x) {
  roundRobin_print(x);
  roundRobin_write('\n');
}

void getPressure() {
  int p = 0;
  #ifndef DEBUG_NO_BREATH
    p = bmp.readPressure() - ATMOS_OFFSET;
  #endif
  if (measure_atmos_state >= 0) {
    measure_atmos_tmp += p;
    measure_atmos_times ++;
    if (measure_atmos_state == 0) {
      atmos_pressure = measure_atmos_tmp / measure_atmos_times;
      // roundRobin_print("E");
      // roundRobin_print(String(atmos_pressure));
      roundRobin_print("R  ");
    }
    measure_atmos_state --;
  } else {
    p -= atmos_pressure;
    p = int(max(0, p) * PRESSURE_MULTIPLIER);
    onPressureChange(p);
    // roundRobin_write('B');
    // roundRobin_print(encodePrintable(p));
    checkNoteEvent();
  }
}

String encodePrintable(int x) {
  // [0, 9024] -> two bytes
  int residual = x % 95;
  int high = (x - residual) / 95;
  high = min(94, high);
  char buffer[3] = { 0 };   // \x00 terminated
  buffer[0] = (char)(high + 32);
  buffer[1] = (char)(residual + 32);
  String result = buffer;
  return result;
}

/******** Called every time TCNT2 = OCR2A ********/
ISR(TIMER2_COMPA_vect) {
  static int phase = 0;
  TCNT2 -= OCR2A;
  OCR1AL = (
    ((abs(phase) >> 7) * amplitude) >> 8
  ) + ((255 - amplitude) >> 1);
  phase += phase_per_sample;
  if (phase >= 32768) {
    phase -= 65536;
  }
}

float frequency = -1;
float old_freq = -1;
void sendFreq(float freq) {
  if (old_freq == freq || isnan(freq)) {
    return;
  }
  old_freq = freq; 
  float target = freq * TUNING;
  byte too_close = OCR2A - 3 - 2;
  while (TCNT2 >= too_close) {
    asm("NOP"); // avoid race condition on volatile
  }
  phase_per_sample = target;
}

int pitch_class;
void onFingerChange() {
  finger_changed = true;
  int i;
  for (i = 0; i < N_SERVOS; i ++) {
    if (! last_capa[i]) {
      break;
    }
  }
  i = (6 - i) * 2;
  if (i >= 6) {
    i --;
  }
  if (i == 11 && last_capa[1] && last_capa[2]) {
    // B flat
    pitch_class = 10;
  } else {
    pitch_class = i;
  }
  updateOctave();
  #ifdef DEBUG_NO_BREATH
    proc_override_synth = false;
  #endif
}

void onPressureChange(int x) {
  #ifdef DEBUG_NO_BREATH
    x = 120;
  #endif
  updateVelocity(pow(x, PARA_EXPONENT));
}

float velocity;
void updateVelocity(float x) {
  velocity = x;
  setExpression();
  update_is_note_on();
  updateOctave();
  long now_millis = millis();
  int dt = now_millis - huhuhu_last_millis;
  huhuhu_last_millis = now_millis;
  float sqrt_velocity = sqrt(max(velocity, ON_THRESHOLD));
  float slope = (sqrt_velocity - huhuhu_smooth_velocity) / (
    dt + huhuhu_smooth_dt * HUHUHU_SMOOTH_TIME
  );
  if (huhuhu_ready && slope >= HUHUHU_THRESHOLD) {
    need_note_event = true;
    // sendDebugMsg("Hu");
    huhuhu_ready = false;
  }
  if (! huhuhu_ready && slope < HUHUHU_RESET_THRESHOLD) {
    huhuhu_ready = true;
  }
  huhuhu_smooth_velocity = (
    HUHUHU_SMOOTH_KEEP * huhuhu_smooth_velocity + 
    HUHUHU_SMOOTH_GAIN * sqrt_velocity
  );
  huhuhu_smooth_dt = (
    HUHUHU_SMOOTH_KEEP * huhuhu_smooth_dt + 
    HUHUHU_SMOOTH_GAIN * dt
  );
}

bool is_note_on;
void update_is_note_on() {
  if (is_note_on) {
    if (velocity < OFF_THRESHOLD) {
      is_note_on = false;
      need_note_event = true;
      // sendDebugMsg("Mu");
    }
  } else {
    if (velocity > ON_THRESHOLD) {
      is_note_on = true;
      proc_override_synth = false;
      need_note_event = true;
      // sendDebugMsg("Tu");
    }
  }
}

void setExpression() {
  if (proc_override_synth) return;
  if (is_note_on) {
    amplitude = byte(round(
      min(255, 
        pow(velocity, .6) / 256
      )
    ));
  } else {
    amplitude = 0;
  }
}

int octave;
void updateOctave() {
  if (is_note_on) {
    #ifdef DEBUG_NO_BREATH
      octave = 5;
    #else
      if (auto_po_mode == AUTO_MODE_OCTAVE) {
        // don't change octave
      } else {
        float y_red = log(velocity) - PARA_OT_INTERCEPT;
        float y_blue = y_red - PARA_OT_HYSTERESIS;
        int red_octave = floor((
          y_red * ONE_OVER_PARA_OT_SLOPE - pitch_class
        ) / 12) + 1;
        int blue_octave = floor((
          y_blue * ONE_OVER_PARA_OT_SLOPE - pitch_class
        ) / 12) + 1;
        if (octave != blue_octave && octave != red_octave) {
          octave = max(0, blue_octave);
          // a little bit un-defined whether it should be red or blue
        }
      }
    #endif
    updatePitch();
  }
}

float pitch2freq(float x) {
  return exp((x + 36.37631656229591) * 0.0577622650466621);
}

int pitch;
float pitch_bend;
void updatePitch() {
  if (is_note_on) {
    int new_pitch; 
    if (auto_po_mode == AUTO_MODE_PITCH) {
      new_pitch = pitch;
    } else {
      new_pitch = pitch_class + 12 * (octave + 1);
    }
    if (pitch != new_pitch || finger_changed) {
      finger_changed = false;
      need_note_event = true;
      // sendDebugMsg("Pi");
    }
    pitch = new_pitch;
    updatePitchBend();
  }
}

void updatePitchBend() {
  if (is_note_on) {
    #ifdef DEBUG_NO_BREATH
      pitch_bend = 0;
    #else
      float in_tune_log_velo = PARA_OT_SLOPE * (
        pitch - 18
      ) + PARA_OT_INTERCEPT_PLUS_HALF_HYST;
      pitch_bend = PITCH_BEND_MULTIPLIER * (
        log(velocity) - in_tune_log_velo
      ) * PARA_PB_SLOPE;
    #endif
    // sendDebugSentence(String(pitch_bend, 2));
    updateFrequency();
  }
}

void updateFrequency() {
  if (proc_override_synth) return;
  frequency = pitch2freq(pitch + pitch_bend);
  // sendDebugSentence(
  //   String(amplitude)
  // );
//  sendDebugSentence(
//    String(pitch_class) + " " + 
//    String(octave) + ", " + 
//    String(round(frequency))
//  );
  sendFreq(frequency);
}

void handleSynth() {
  if (midi_buf_push_i != midi_buf_pop_i) {
    // non empty
    if (
      millis() >= sync_clock_zero + midi_buf_dt[midi_buf_pop_i]
    ) {
      int pitch = midi_buf_pitch[midi_buf_pop_i];
      if (pitch == 128) {
        // rest
        amplitude = 0;
      } else {
        sendFreq(pitch2freq(pitch));
        amplitude = 200;
      }
      sync_clock_zero += midi_buf_dt[midi_buf_pop_i];
      midi_buf_pop_i = (midi_buf_pop_i + 1) % MIDI_BUF_SIZE;
    }
  }
  if (proc_override_synth && amplitude != 0) {
    amplitude -= 40;
    amplitude = max(40, amplitude);
  }
}

void checkNoteEvent() {
  if (need_note_event) {
    need_note_event = false;
    huhuhu_ready = false;
    // sendDebugMsg("Ne");
    roundRobin_write('N');
    if (is_note_on) {
      roundRobin_print(encodePrintable(pitch));
    } else {
      // rest
      roundRobin_print(encodePrintable(129));
    }
    if (auto_po_mode != AUTO_MODE_NONE) {
      if (millis() < auto_po_commit_when) {
        // pitch doens't change
      } else {
        if (auto_po_mode == AUTO_MODE_PITCH) {
          pitch = auto_po_next;
        } else {
          octave = auto_po_next;
        }
        // sendDebugSentence(String(new_pitch));
        auto_po_commit_when = millis() + AUTO_PO_COMMIT_TIME;
        need_note_event = true;
      }
    }
  }
}

bool work_out_phase = 0;
void workOut() {
  work_out_phase = ! work_out_phase;
  int angle;
  if (work_out_phase) {
    angle = 84;
  } else {
    angle = 102;
  }
  for (int i = 0; i < N_SERVOS; i ++) {
    setServo(i, angle);
  }
}
