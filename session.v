module basex 

import net
import io
import crypto.md5
import time
import math

[noinit]
pub struct Session {
	username string
	host string
	port int
	mut:
		conn net.TcpConn 
}

// BaseX Session API --------------------------------------------------
// Create and return session with host, port, username and password:
// session := basex.session('127.0.0.1', 8984, 'admin', 'admin')
pub fn create(host string, port int, username string, password string) ?Session {
	mut c := net.dial_tcp('$host:$port') or { 
		return error('Connection: ${host}:${port}')
	} 
	c.set_read_timeout(150 * time.millisecond)
	c.set_blocking(false) or {println(err)}
	mut session := Session {
		username: username
		host: host
		port: port
		conn: c
	}
	session.auth(username, password) or {}
	return session
}

// send a command and return the result:
pub fn (mut session Session) execute(command string) !(string,string) {
	session.request('','${command}')
	result := session.next() or {''.bytes()}
	info := session.next() or {''.bytes()}
	session.next() or {''.bytes()} //panic("command error")}
	return result.bytestr(), info.bytestr()
}

// Create a database from an input string:
pub fn (mut session Session) createdb(name string, mut input io.Reader) ?[]u8 {
	return session.exec_info('\x08',name, mut input)
}

// Add a document to the current database from an input stream:
pub fn (mut session Session) add(path string, mut input io.Reader) ?[]u8 {
	return session.exec_info('\x09',path,mut input)
}

// Put a document with the specified mut input stream:
pub fn (mut session Session) put(path string, mut input io.Reader) ?[]u8 {
	return session.exec_info('\x0C',path,mut input) or {none}
}

// Put a binary resource at the specified path:
pub fn (mut session Session) put_binary(path string, mut input io.Reader) ![]u8 {
	return session.exec_info('\x0D', path, mut input)!
}

// Create query instance with session and query:
pub fn (mut session Session) new_query(query_str string)! Query {
	//clearing buffer
	session.next() or {''.bytes()}
  _ := session.next() or {''.bytes()}

	session.next() or {}
	session.request('\x00', query_str)
	mut id := session.next() or {
		println('bad new query!!!')
		panic(err)
	}
   session.error_check()!
	q := Query {
		id: id.bytestr()
		session: session
	}
	return q
}

// Session Support functions --------------------------------------------------
fn (mut session Session) exec_info(code string, path string, mut input io.Reader) ?[]u8 {
	session.request_with_input(code, path, mut input)
	info := session.next()?
	session.error_check() or {return none}
	return info
}

fn (mut session Session) error_check() !{
	readb := new_readb(mut session.conn, false) 
	if err := readb() {
		if err == 1 {
	 		return error('BaseX Server responded with an error.')
		}
	} else { 
	 		return error('BaseX Server responded with an error.')
	}
} 

// make a database request 
fn (mut session Session) request(code string, arg string) {
	//write cmd code and args
	mut cmd := code.bytes()
	cmd << arg.bytes()
	cmd << u8(0)
	writestr := new_writestr(mut session.conn, false)
	writestr(cmd.bytestr()) or {}
} 

// make a database request 
fn (mut session Session) request_int(code string, arg int) {
	mut cmd := code.bytes()
	cmd << u8(arg)
	cmd << u8(0)
	dump(cmd)
	writestr := new_writestr(mut session.conn, false)
	writestr(cmd.bytestr()) or {}
} 

// make a database request with given input Reader
fn (mut session Session) request_with_input(code string, arg string, mut reader io.Reader) {
	mut cmd := code.bytes()
	cmd << arg.bytes()
	cmd << u8(0)
	writestr := new_writestr(mut session.conn, false)
	writestr(cmd.bytestr()) or {}
	readb := new_readb(mut reader, false)
	writeb := new_writeb(mut session.conn, false)
	for {
		if b := readb() {
			if b == u8(255) || b == u8(0) {
				writeb(u8(255)) or {break}
			} 
			writeb(b) or {break}
		} else {break}
	}
	writeb(u8(0)) or {}
}

// read next field in session reponse
fn (mut session Session) next() ?[]u8 {
	mut field := []u8{}
	readb := new_readb(mut session.conn, false)
	for {
		mut b := readb() or {break}
	//	dump(b)
		if b == 0 {break}
		if b == 255 {
			b = readb() or {break}
		}
		field << b
	}
	return 
		if field.len < 1 {none}
		else {field}
}

// authorize the connection
fn (mut session Session) auth(username string, password string) ! {
	mut result := session.next() or {
		return error('bad next on result')
	}
	data := result.bytestr().split(':')	
	realm := data[0]
	timestamp := data[1]
	token := get_token(username, password, realm , timestamp) 
	auth := username + '\0' + token + '\0'
	session.conn.wait_for_write() or {}
	session.conn.write(auth.bytes()) or {
		return error('Auth request')
	}
	readb := new_readb(mut session.conn, false)
	if is_authenticated := readb() {
		if is_authenticated != 0 {
			error('Auth: ${username}')
		}
	}
}

// Other functions --------------------------------------------------
// Close the session:
pub fn (mut session Session) close() {
		session.conn.close() or {}

}

// get a token for autorization
fn get_token(username string, password string, realm string, timestamp string) string {
	stage1 := md5.hexhash('$username:$realm:$password')
	token := md5.hexhash(stage1 + timestamp)
	return token 
}

struct StringReader {
    data []u8
    mut:
    	offset int
}

fn new_string_reader(str string) StringReader{
	//dump(str)
    return StringReader {
        data: str.bytes()
    }
}

fn (mut reader StringReader) read(mut ba []u8) !int {
  mut frameend := math.min(reader.offset + ba.len, reader.data.len) 
    ba = reader.data[reader.offset..frameend]
    reader.offset = frameend 
    return ba.len
}

fn encode(ba []u8) []u8 {
	mut newba := []u8{}
	for i in 0..ba.len {
		if ba[i] == 255 || ba[i] == 0 {
			newba << u8(255)
		}
		newba << ba[i]
	}
	return newba
}

// creates a new function to read a byte from a given Reader
fn new_readb(mut reader io.Reader, decode bool) fn () ?u8 {
	return fn [mut reader, decode] () ?u8 {
		mut ba := []u8 {len: 1, cap: 1}
		mut len := reader.read(mut ba) or {return none}
		if len != 1 { return none}

		if decode && ba[0] == 255 {
			len = reader.read(mut ba) or {return none}
			if len == 0 { return none}
		}
		return 
			if len == 0 {none}
			else {ba[0]}
	}
}

// creates a new function to write a byte to a given Writer
fn new_writeb(mut writer io.Writer, encode bool) fn (u8) !int {
	return 
		fn [mut writer, encode] (b u8) !int {
			mut ba := []u8{len: 1, cap: 1}
			mut len := 0
			if encode && (b == 0 || b == 255) {
				ba = [u8(255)]
				lw := writer.write(ba)!
				if lw == 1 {len++}
			}
			ba = [b]
			lw := writer.write(ba)!
			if lw == 1 {len++}
			return len
		}
}

// creates a new function to write a string to a given Writer
fn new_writestr(mut writer io.Writer, encode bool) fn (string) !int {
	return 
		fn [mut writer, encode] (str string) !int {
			if encode {
				mut ba := []u8{len:str.len}
				for c in str.bytes() {
					if c == u8(255) || c == u8(0) {
						ba << u8(255)
					}
					ba << c
				}
				len := writer.write(ba) or {panic(err)}
				return len
			} else {
				len := writer.write(str.bytes()) or {panic(err)}
				return len
			}
		}
}
