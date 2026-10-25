#!/usr/bin/env python3
"""Generate original procedural instrument samples and a compact SF2 (CC0).
Requires numpy only. Not needed to build the iOS app; the .sf2 is included.
"""
import math
import struct
from pathlib import Path
import numpy as np

OUT = Path(__file__).parent / 'SimplyKeys' / 'Sounds' / 'SimplyKeys.sf2'
SR = 22050
ANCHORS = [0, 12, 24, 36, 48, 60, 72, 84, 96, 108, 120] # full MIDI range, C-1..G9
PRESETS = [
    (0, 'Grand Piano'), (4, 'Electric Piano'), (10, 'Music Box'),
    (11, 'Vibraphone'), (12, 'Marimba'), (16, 'Organ'),
    (21, 'Accordion'), (24, 'Acoustic Guitar'), (26, 'Electric Guitar'),
    (32, 'Bass Guitar'), (40, 'Violin'), (42, 'Cello'),
    (46, 'Harp'), (48, 'Strings'), (56, 'Trumpet'), (57, 'Trombone'),
    (65, 'Saxophone'), (68, 'Oboe'), (71, 'Clarinet'),
    (73, 'Flute'), (80, 'Synth')
]


def sample(patch, midi):
    frequency = 440 * (2**((midi - 69)/12))
    sustain = patch in (16,21,40,42,48,56,57,65,68,71,73,80)
    duration = 1.7 if not sustain else 1.5
    n = int(SR * duration)
    t = np.arange(n) / SR
    x = np.zeros(n, dtype=np.float64)
    if patch == 0:
        # Inharmonic strings + multi-string detuning and a sharp hammer transient.
        for detune in [-0.00045, 0.0, 0.00042]:
            for h in range(1, 12):
                fh = frequency * h * np.sqrt(1 + 0.00012 * h*h)
                if fh > SR * 0.43: break
                amp = (1/h**1.48) * np.exp(-t * (0.65 + 0.13*h))
                x += (0.32 / 3) * amp * np.sin(2*np.pi*fh*(1+detune)*t + h*0.17)
        x *= (1 - np.exp(-t*320))
        x += 0.018 * np.exp(-t*38) * np.sin(2*np.pi*frequency*5.9*t) * (1-np.exp(-t*600))
    elif patch == 4:
        # Electric tines / FM Rhodes-like sound.
        tone = np.sin(2*np.pi*frequency*t + 2.7*np.exp(-t*4.2)*np.sin(2*np.pi*frequency*2*t))
        overtone = 0.35*np.sin(2*np.pi*frequency*4.02*t)*np.exp(-t*3.7)
        x = 0.39*(tone*np.exp(-t*0.8) + overtone) * (1 - np.exp(-t*150))
    elif patch == 10:
        # Small bright struck metallic instrument.
        for mul, amp, d in [(1,0.36,1.3),(2.02,.17,2.5),(3.92,.13,3.7),(5.42,.09,4.8)]:
            if frequency*mul < SR*.45:
                x += amp*np.sin(2*np.pi*frequency*mul*t)*np.exp(-d*t)
        x *= (1-np.exp(-t*320))
    elif patch == 16:
        for harm, vol in [(1,.35),(2,.20),(3,.13),(4,.09),(6,.12),(8,.06)]:
            if frequency*harm < SR*.44:
                x += vol*np.sin(2*np.pi*frequency*harm*t+0.1*harm)
        x *= (1-np.exp(-t*190))*(0.96 + 0.04*np.sin(2*np.pi*5.2*t))
    elif patch in (40,42,48):
        for detune in [-.004, .003, .0004]:
            for h in range(1, 13):
                if frequency*h > SR*.42: break
                x += (.082/h**1.23)*np.sin(2*np.pi*frequency*h*(1+detune)*t)
        x *= (1-np.exp(-t*16))*(.97 + .03*np.sin(2*np.pi*5.1*t))
    elif patch in (56,57,65,68,71):
        env = 1-np.exp(-t*33)
        vibrato = 1 + .0025*np.sin(2*np.pi*5.1*t)*(1-np.exp(-t*3))
        phase = 2*np.pi*frequency*(t + .0025/(2*np.pi*5.1)*(1-np.cos(2*np.pi*5.1*t)))
        for h in range(1, 15):
            if frequency*h > SR*.43: break
            x += (.3/h**1.1)*np.sin(h*phase + h*.15) * (1-np.exp(-t*(15+3*h)))
        x *= env
    elif patch in (11, 12, 46):
        # Metallic/mallet/harp-like struck sounds with filtered upper partials.
        decay = {11: 1.2, 12: 2.8, 46: 1.65}[patch]
        components = [(1, .39), (2, .12), (3.98 if patch==11 else 3, .09)]
        for h, amp in components:
            if frequency*h < SR*.45:
                x += amp*np.sin(2*np.pi*frequency*h*t)*np.exp(-t*decay*(1+.24*h))
        x *= (1-np.exp(-t*(300 if patch != 46 else 170)))
    elif patch in (24, 26, 32):
        # Plucked strings with progressively darker timbre.
        brightness = {24: 1.38, 26: 1.05, 32: 1.75}[patch]
        for h in range(1, 15):
            if frequency*h > SR*.44: break
            x += (.36/(h**brightness))*np.sin(2*np.pi*frequency*h*t)*np.exp(-t*(.9+h*.16))
        x *= (1-np.exp(-t*260))
    elif patch == 21:
        for h in range(1, 11):
            if frequency*h > SR*.44: break
            x += (.28/(h**1.4))*np.sin(2*np.pi*frequency*h*t)                 + (.12/(h**1.6))*np.sin(2*np.pi*frequency*h*1.003*t)
        x *= 1-np.exp(-t*45)
    elif patch == 73:
        x = (.5*np.sin(2*np.pi*frequency*t) + .055*np.sin(2*np.pi*frequency*2*t))
        x *= 1-np.exp(-t*28)
    elif patch == 80:
        phase = 2*np.pi*frequency*t
        for h in range(1, 14):
            if frequency*h > SR*.45: break
            x += (.24/h)*np.sin(h*phase)
        x *= 1 - np.exp(-t*90)
    # Keep a few milliseconds of headroom, avoid clipping, and normalize consistently.
    peak = max(np.max(np.abs(x)), 0.01)
    x = x * (0.70 / max(peak, .70))
    fade = min(450, n//10)
    if not sustain: x[-fade:] *= np.linspace(1,0,fade)
    return x, sustain


def chunk(id, data):
    if len(data)&1: data += b'\x00'
    return id + struct.pack('<I', len(data)) + data

def name20(s): return s.encode('ascii')[:19].ljust(20,b'\x00')
def sfgen(op, amount): return struct.pack('<HH',op,amount & 0xffff)
def timecents(sec): return int(1200*math.log2(sec)) & 0xffff

sample_pcm = bytearray()
sample_headers = []
inst_bags = []
inst_gens = []
instruments = []
for prog, label in PRESETS:
    instruments.append((label,len(inst_bags)))
    for k, anchor in enumerate(ANCHORS):
        pcm, sustain = sample(prog,anchor)
        start = len(sample_pcm)//2
        pcm16 = np.clip(pcm*32767, -32768,32767).astype('<i2')
        sample_pcm += pcm16.tobytes()
        end = len(sample_pcm)//2
        # Leave SF2's mandated guard samples after every sample.
        sample_pcm += b'\x00' * 92
        # Sustain instruments loop their final ~200ms of audio.
        loop_start = start + int(SR*1.1) if sustain else start
        loop_end = start + int(SR*1.4) if sustain else end
        sid = len(sample_headers)
        sample_headers.append((f'{label[:9]}{anchor}',start,end,loop_start,loop_end,SR,anchor))
        inst_bags.append(len(inst_gens))
        # Key zones partition at halfway between C anchor notes.
        lo = 0 if k==0 else (ANCHORS[k-1]+anchor)//2 + 1
        hi = 127 if k==len(ANCHORS)-1 else (anchor+ANCHORS[k+1])//2
        inst_gens.append(sfgen(43, lo | hi << 8)) # keyRange
        inst_gens.append(sfgen(38,timecents(.17 if sustain else .28))) # releaseVolEnv
        if sustain: inst_gens.append(sfgen(54,1)) # sampleModes: loop while key held
        inst_gens.append(sfgen(53,sid)) # sampleID (last)

# The terminal IBAG, IGEN, IMOD entries are mandatory.
instrument_headers = b''.join(name20(n)+struct.pack('<H', bag) for n,bag in instruments)
instrument_headers += name20('EOI') + struct.pack('<H',len(inst_bags))
ibag = b''.join(struct.pack('<HH',gen,0) for gen in inst_bags)
ibag += struct.pack('<HH',len(inst_gens),0)
igen = b''.join(inst_gens) + sfgen(0,0)

presets = b''
pbags = b''
pgen = b''
for index, (prog,label) in enumerate(PRESETS):
    presets += name20(label)+struct.pack('<HHHIII',prog,0,index,0,0,0)
    pbags += struct.pack('<HH',index,0)
    pgen += sfgen(41,index)  # instrument assignment
presets += name20('EOP') + struct.pack('<HHHIII',0,0,len(PRESETS),0,0,0)
pbags += struct.pack('<HH',len(PRESETS),0)
pgen += sfgen(0,0)

shdr = b''
for nam,sta,end,ls,le,sr,orig in sample_headers:
    shdr += name20(nam)+struct.pack('<IIIIIBbHH',sta,end,ls,le,sr,orig,0,0,1)
last = len(sample_pcm)//2
shdr += name20('EOS')+struct.pack('<IIIIIBbHH',last,last,last,last,SR,0,0,0,1)

info = chunk(b'LIST', b'INFO'+chunk(b'ifil',struct.pack('<HH',2,1))
             +chunk(b'isng',b'EMU8000\x00')+chunk(b'INAM',b'Simply Keys Original Instruments\x00')
             +chunk(b'ICRD',b'2026\x00')+chunk(b'IENG',b'OpenAI for Simply Keys\x00')
             +chunk(b'ICOP',b'Original generated sounds - CC0 1.0\x00'))
sdta = chunk(b'LIST', b'sdta'+chunk(b'smpl',bytes(sample_pcm)))
pdta = chunk(b'LIST',b'pdta'+chunk(b'phdr',presets)+chunk(b'pbag',pbags)
             +chunk(b'pmod',bytes(10))+chunk(b'pgen',pgen)
             +chunk(b'inst',instrument_headers)+chunk(b'ibag',ibag)
             +chunk(b'imod',bytes(10))+chunk(b'igen',igen)+chunk(b'shdr',shdr))
data = b'sfbk'+info+sdta+pdta
OUT.write_bytes(chunk(b'RIFF',data))
print('Wrote',OUT,'size',OUT.stat().st_size, 'samples',len(sample_headers))
