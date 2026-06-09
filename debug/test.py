#! /usr/bin/env -S python -u

import serial
import sys
import time

class Uart:
    def __init__(self, serial_port : str, baudrate : int, timeout : float = 0.1):
        self.dut = serial.Serial(
                port     = serial_port,
                baudrate = baudrate,
                timeout  = timeout,
                parity   = serial.PARITY_NONE,
                stopbits = serial.STOPBITS_ONE,
                bytesize = serial.EIGHTBITS
                )
    def send(self, msg : str):
        try:
            self.dut.write(msg.encode(encoding="utf-8"))
        except KeyboardInterrupt:
            sys.exit(-1)
        except:
            print("Uart.send: Error")

    def read(self, blocking : bool = True) -> str:
        while blocking:
            try:
                res = self.dut.readline()
            except KeyboardInterrupt:
                sys.exit(-1)
            if res != b'':
                blocking = False
        return res.decode("utf-8").rstrip()

dut = Uart('/dev/ttyUSB1', 2000000)

print("Waiting for initial signature:", end='')

assert dut.read() == 'MFJ'
assert dut.read() == 'FFEF13CE'

print("  Got it!")

print("Waiting five seconds:", end='')

time.sleep(5)

print("  Done!")

print("Sending keyboard commands:", end='')

dut.send('hde22r22u22ue22222222222s')

print("  Done!")

print("Waiting")

while True:
    print(dut.read(blocking = True))

