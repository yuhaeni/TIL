# 레지스터 (PC, MAR, MBR, IR)

> 날짜: 2026-03-26

## 내용


### 레지스터
<img width="712" height="459" alt="image" src="https://github.com/user-attachments/assets/4e3701a0-1935-4441-805e-b0779c788b4a" />


CPU 내부의 임시 저장 장치로, 프로그램 속 명령어와 데이터는 실행 전후로 반드시 레지스터에 저장된다.

> 상용화된 CPU 속 레지스터들은 CPU마다 이름, 크기, 종류가 매우 다양하다.

<img width="684" height="338" alt="image" src="https://github.com/user-attachments/assets/2ed977d1-6e78-427e-a976-dcad053424d9" />

### 프로그램 카운터 (PC; Program Counter)

**다음에 실행할 명령어의 메모리 주소**를 저장하여 실행 순서를 관리하는 레지스터이다.

- 명령어 포인터(IP; Instruction Pointer)라고 부르는 CPU도 있다.

### 메모리 주소 레지스터 (MAR; Memory Address Register)

**CPU가 접근하려는 메모리 주소**를 저장하여 주소 버스로 내보내는 레지스터이다.

- 주소 버스라는 통로를 통해 메모리에게 주소를 전달하는데, 그 사이에 MAR을 거친다.

> CPU [ PC(주소 기억) → MAR(주소 담기) ] → 주소 버스(전달) → 메모리(읽기)

### 메모리 버퍼 레지스터 (MBR; Memory Buffer Register)

메모리와 주고받을 값(**데이터와 명령어**)을 저장하는 레지스터이다.

- 메모리에서 읽은 데이터는 데이터 버스를 통해 MBR로 전달된다.

> 메모리 → 데이터 버스 → MBR

### 명령어 레지스터 (IR; Instruction Register)

메모리에서 방금 읽어 들인 **명령어**를 저장하는 레지스터이다.

- 제어장치는 명령어 레지스터 속 명령어를 받아들이고, 이를 해석한 뒤 제어 신호를 내보낸다.

## 참고

- 혼자 공부하는 컴퓨터 구조+운영체제
