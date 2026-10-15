package main

import (
	"bytes"
	"encoding/binary"
	"net"
)

func checksum(b []byte) uint16 {
	var n uint32
	for len(b) > 1 {
		n += uint32(binary.BigEndian.Uint16(b))
		b = b[2:]
	}
	if len(b) > 0 {
		n += uint32(b[0]) << 8
	}
	for n>>16 != 0 {
		n = (n & 65535) + (n >> 16)
	}
	return ^uint16(n)
}

func probePacket(src net.IP, seq uint16, nonce []byte) []byte {
	b := make([]byte, 28+len(nonce))
	b[0] = 0x45
	binary.BigEndian.PutUint16(b[2:], uint16(len(b)))
	b[8] = 64
	b[9] = 1
	copy(b[12:16], src.To4())
	copy(b[16:20], net.IPv4(1, 1, 1, 1).To4())
	binary.BigEndian.PutUint16(b[10:], checksum(b[:20]))
	b[20] = 8
	binary.BigEndian.PutUint16(b[24:], 0x4f46)
	binary.BigEndian.PutUint16(b[26:], seq)
	copy(b[28:], nonce)
	binary.BigEndian.PutUint16(b[22:], checksum(b[20:]))
	return b
}

func isProbeReply(b []byte, nonce []byte) bool {
	if len(b) < 28 || b[0]>>4 != 4 || b[9] != 1 {
		return false
	}
	off := int(b[0]&15) * 4
	if off < 20 || len(b) < off+8+len(nonce) {
		return false
	}
	return net.IP(b[12:16]).Equal(net.IPv4(1, 1, 1, 1)) && b[off] == 0 && binary.BigEndian.Uint16(b[off+4:]) == 0x4f46 && bytes.Equal(b[off+8:], nonce)
}
