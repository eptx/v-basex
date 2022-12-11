module basex 

struct Query {
	id 	string 	
	pos int 
	mut:
		session Session
}

pub fn (mut q Query) close() {
	q.session.request('\x02', '${q.id}') 
}

// Bind an external variable:
// The bind_value_bind_value_type can be an empty string.
pub fn (mut q Query) bind(name string, value string, value_type string) ! {
	mut cmd := '\x03'.bytes()
	cmd << q.id.bytes()
	cmd << 0
	cmd << encode(name.bytes())
	cmd << 0
	cmd << encode(value.bytes())
	if value_type.len > 0 {
		cmd << 0 
		cmd << encode(value_type.bytes())
	} else {
		cmd << 0
	}
	cmd << 0
	q.session.conn.write(cmd) or {
		println(err)
		panic('bad write')}
	q.session.error_check()!
	q.session.error_check()!
}

//??? not sure how or why to use this after brief search on basex for an example
// Bind the context item:
// The bind_value_bind_value_type can be an empty string.
pub fn (mut q Query) context(name string, value string, value_type string) {
	//q.execute('\0x0E${name}\0${value}\0${value_type}')
}

pub fn (mut q Query) results()! [][]u8 {
  mut results := [][]u8{}
	q.session.request('\x04', '${q.id}')
	for { 
		result := q.session.next() or {
			break
		}
		results << result
	}
	q.session.error_check()!
	return results
}

// Execute the query and return the result:
pub fn (mut q Query) execute()  ![]u8 {
	q.session.request('\x05', q.id) 
	result := q.session.next() or { 
		return error('Failed query execute: ${q.id}')
	}
	q.session.error_check()!
	return result
}

pub fn (mut q Query) info()! []u8 {
	q.session.request('\x06', q.id)
	result := q.session.next() or {
		return error('Failed query info: ${q.id}')
	}
	return result
}

// read next field in session reponse
pub fn (mut q Query) next() ?[]u8 {
	mut field := []u8{}
	readb := new_readb(mut q.session.conn, false)
	for {
		mut b := readb() or {break}
		if b == 0 || b ==  10 {break}
		if b == 255 {
			b = readb() or {break}
		}
		field << b
	}
	return 
		if field.len < 1 {none}
		else {field}
}

// Execute the query and wait for calls to next:
pub fn (mut q Query) execute_iterate() {
	q.session.request('\x05', q.id) 
}

// Return serialization parameters:
pub fn (mut q Query) options() ?string {
	q.session.request('\x07', q.id)
	result := q.session.next() or {
	  return error('Failed options execute: ${q.id}')
	}
	q.session.error_check() or {}
	return result.bytestr()
}

// Return if the query may perform updates:
pub fn (mut q Query) updating() bool {
	q.session.request('\x1E', q.id)
	if isupdating := q.session.next(){
		q.session.error_check() or {}
		if isupdating.bytestr() == 'true' {true } else {false} 
	} 
	return false

}

// Not implemented. Execute returns full.
// pub fn (mut q Query) full()

// Not implemented. Seems unnecesary with option types.
// pub fn (mut q Query) more()
