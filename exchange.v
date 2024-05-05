module main

import net
import time

struct Exchange {
mut:
	is_end  bool
	end_sig chan bool = chan bool{cap: 1}
	raddr   string
	// TLS
	lconn &net.TcpConn
}

fn new_exchange(lconn &net.TcpConn, remoteAddr string) Exchange {
	return Exchange{
		raddr: remoteAddr
		lconn: lconn
	}
}

pub fn (mut me Exchange) start() ! {
	go me.start_2()
	/*
	go fn () {
		mut rconn := net.dial_tcp(me.raddr)!
		go me.exchange(me.lconn, mut rconn)
		go me.exchange(rconn, mut me.lconn)
		_ = <-me.end_sig
		me.lconn.close() or {} // ignore
		rconn.close() or {} // ignore
		println('all exchange end')
	}()
	*/
}

pub fn (mut me Exchange) start_2() ! {
	mut rconn := net.dial_tcp(me.raddr)!
	go me.exchange(me.lconn, mut rconn)
	go me.exchange(rconn, mut me.lconn)
	_ = <-me.end_sig
	me.lconn.close() or {} // ignore
	rconn.close() or {} // ignore
	println('all exchange end')
}

fn (mut me Exchange) exchange(from net.TcpConn, mut to net.TcpConn) {
	mut buf := []u8{len: 1024}
	mut num_read := 0
	mut num_write := 0
	for {
		num_read = from.read(mut buf) or {
			println('xxxx from.read: ${err}')
			-1
		}

		if num_read <= 0 {
			me.end()
			break
		}

		num_write = to.write_ptr(buf[0], num_read) or {
			println('to.write_ptr error: ${err}')
			-1
		}
		if num_read != num_write {
			println('xxxx write faild')
			me.end()
			break
		}
	}
}

fn (mut me Exchange) end() {
	if me.is_end {
		return
	}

	me.is_end = true
	me.end_sig <- true
}

struct ReverseProxy {
	local  string
	remote string
mut:
	running bool
}

fn new_reverse_proxy(local string, remote string) ReverseProxy {
	return ReverseProxy{
		local: local
		remote: remote
	}
}

fn (mut me ReverseProxy) serve() ! {
	mut server := net.listen_tcp(.ip, me.local) or {
		println('xxxx net.listen_tcp: ${err}')
		panic(err)
	}
	println('proxy listen: ${server.addr()!}')

	me.running = true

	for ; me.running; {
		mut lconn := server.accept()!
		if !me.running {
			break
		}
		println('accept new connect')
		mut e := new_exchange(lconn, me.remote)
		e.start() or { println('xxxx start: ${err}') }
	}
	println('serve end')
}

fn (mut me ReverseProxy) quit() {
	me.running = false
	mut rconn := net.dial_tcp(me.local) or { &net.TcpConn{} } // ignore
	rconn.close() or {} // ignore
}

fn main() {
	mut rp := new_reverse_proxy(':9923', '45.56.81.220:80')
	go fn (mut rproxy ReverseProxy) {
		time.sleep(10000 * time.millisecond)
		rproxy.quit()
	}(mut &rp)
	rp.serve() or { println('xxxx listen: ${err}') }
}
