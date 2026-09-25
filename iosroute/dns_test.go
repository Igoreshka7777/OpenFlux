package iosroute

import (
	"net"
	"testing"

	"golang.org/x/net/dns/dnsmessage"
)

func TestDNSHelpers(t *testing.T) {
	name := dnsmessage.MustNewName("blocked.example.")
	queryMessage := dnsmessage.Message{
		Header:    dnsmessage.Header{ID: 42, RecursionDesired: true},
		Questions: []dnsmessage.Question{{Name: name, Type: dnsmessage.TypeAAAA, Class: dnsmessage.ClassINET}},
	}
	query, err := queryMessage.Pack()
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := ParseQuestion(query)
	if err != nil || parsed.Domain != "blocked.example." || parsed.Type != dnsmessage.TypeAAAA {
		t.Fatalf("parsed question: %+v, %v", parsed, err)
	}
	aQuery, err := BuildAQuery(parsed)
	if err != nil {
		t.Fatal(err)
	}
	aParsed, err := ParseQuestion(aQuery)
	if err != nil || aParsed.Type != dnsmessage.TypeA || aParsed.ID != 42 {
		t.Fatalf("A query: %+v, %v", aParsed, err)
	}

	responseMessage := dnsmessage.Message{
		Header:    dnsmessage.Header{ID: 42, Response: true},
		Questions: []dnsmessage.Question{{Name: name, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET}},
		Answers: []dnsmessage.Resource{{
			Header: dnsmessage.ResourceHeader{Name: name, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET, TTL: 30},
			Body:   &dnsmessage.AResource{A: [4]byte{203, 0, 113, 7}},
		}},
	}
	response, err := responseMessage.Pack()
	if err != nil {
		t.Fatal(err)
	}
	ips := IPv4Answers(response)
	if len(ips) != 1 || !ips[0].Equal(net.ParseIP("203.0.113.7")) {
		t.Fatalf("IPv4 answers: %v", ips)
	}
	empty, err := EmptyAAAA(response)
	if err != nil {
		t.Fatal(err)
	}
	if len(IPv4Answers(empty)) != 0 {
		t.Fatal("answer was not removed")
	}
}
