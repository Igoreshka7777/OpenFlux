package iosroute

import (
	"errors"
	"net"

	"golang.org/x/net/dns/dnsmessage"
)

type DNSQuestion struct {
	Domain string
	Type   dnsmessage.Type
	Name   dnsmessage.Name
	ID     uint16
}

func ParseQuestion(query []byte) (DNSQuestion, error) {
	var msg dnsmessage.Message
	if err := msg.Unpack(query); err != nil {
		return DNSQuestion{}, err
	}
	if len(msg.Questions) == 0 {
		return DNSQuestion{}, errors.New("DNS question missing")
	}
	q := msg.Questions[0]
	return DNSQuestion{Domain: q.Name.String(), Type: q.Type, Name: q.Name, ID: msg.Header.ID}, nil
}

func IPv4Answers(answer []byte) []net.IP {
	var msg dnsmessage.Message
	if err := msg.Unpack(answer); err != nil {
		return nil
	}
	var ips []net.IP
	for _, resource := range msg.Answers {
		if a, ok := resource.Body.(*dnsmessage.AResource); ok {
			ips = append(ips, net.IP(a.A[:]))
		}
	}
	return ips
}

func BuildAQuery(q DNSQuestion) ([]byte, error) {
	msg := dnsmessage.Message{
		Header:    dnsmessage.Header{ID: q.ID, RecursionDesired: true},
		Questions: []dnsmessage.Question{{Name: q.Name, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET}},
	}
	return msg.Pack()
}

func EmptyAAAA(answer []byte) ([]byte, error) {
	var msg dnsmessage.Message
	if err := msg.Unpack(answer); err != nil {
		return nil, err
	}
	msg.Answers = nil
	return msg.Pack()
}
