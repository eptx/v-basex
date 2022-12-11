module basex

// launch an instance of basex as follows...
// ./basex/bin/basexhttp -c password
// I use entr to rerun the test after making a source code change...
// find . -name '*.v' | entr -cr v -stats -cg test basex/basex_test.v

import os
import crypto.md5

fn setup() Session {
	return basex.create('127.0.0.1', 1984, 'test', 'test') or {panic('No Session')}
}

fn test_session() {
	mut session := 	setup()
	defer {
		session.close()
	}
	mut response, mut info := session.execute('INFO')!
	assert response.contains('INLINELIMIT'), 'Failed session.info'
	
	mut reader := basex.new_string_reader('<hello_test1/>')
  info = session.createdb('test1', mut reader)!.bytestr()
	response, info = session.execute('LIST')!
	assert response.contains('test1')
	
	// check for content	
	response, info = session.execute('list test1')!
	assert response.contains('test1.xml')
	
	// make sure it gets dropped
	session.execute('drop database test1')!
	response, info = session.execute('list')!
	assert !response.contains('test1')
	
	// create database with a execute call
	session.execute('create database test2 <hello_test2/>')!
	response, info = session.execute('list')!
	assert response.contains('test2')
	
	// check for content, info = session.execute('list test2')!
	assert response.contains('test2.xml')
	
	// make sure it gets dropped
	session.execute('drop database test2')!
	response, info = session.execute('list')!
	assert !response.contains('test2')
	
	// simple xquery
	response, info = session.execute('xquery 2 + 3')!
	assert response == '5'
 	
 	response, info = session.execute('create database test3 <stuff>test3</stuff>')!
	info = session.add('upload', mut basex.new_string_reader('<abc>to test3</abc>'))!.bytestr()
 	info = session.add('test3/hello1', mut basex.new_string_reader(r'<hello1/>'))!.bytestr()
	response, info = session.execute('list test3')!
	assert response.contains('test3/hello')
}

fn test_binary() {
	mut session := 	setup()
	defer {
		session.close()
	}
	mut cmd := 'create database library'
 	mut response, mut info := session.execute(cmd)!
	file_types := ['csv', 'v', 'jpg', 'pdf']
	for t in file_types {
		filetemp := os.read_bytes('basex/test/testdata/example.${t}')!
		mut file := os.open('basex/test/testdata/example.${t}')!
		defer {
			file.close()
		}
		file_md5 := md5.hexhash(filetemp.bytestr())
		put_info := session.put_binary('example.${t}', mut file) or {panic(err)}
		cmd = ' BINARY GET example.${t}' 
		response, info = session.execute(cmd)!
		infile_md5 := md5.hexhash(response)
		assert file_md5 == infile_md5
	}
}

fn test_query() {
	mut session := 	setup()
	defer {
		session.close()
	}
	mut response, mut info := session.execute('xquery 2 + 3')!
	assert response == '5'

	info = session.createdb('test_qdb', mut basex.new_string_reader('<qdb/>'))?.bytestr()
	response, info = session.execute('list test_qdb')!
	assert response.contains('test_qdb')

	mut qstr := '44 + 11'
	mut query :=  session.new_query(qstr)!
	response = query.execute()!.bytestr()
	query.close()
	assert response == '55'

	qstr = r'declare option output:method "xml";
	let $message := "Hello World"
			return <results><message>{$message}</message></results>'
	query = session.new_query(qstr)!
	options := query.options()?
	assert options == 'method=xml'
	
	response = query.execute()!.bytestr()
	assert response == '<results><message>Hello World</message></results>'

	response = query.info()!.bytestr()
	query.close()
	qstr = r'
		xs:string("abc"),
		xs:integer("123"),
		xs:float("1.23"),
		<el>cde</el>'
	query = session.new_query(qstr)!
	results := query.results()!
	assert results[0][0] == 38
	assert results[1][0] == 52
	assert results[2][0] == 48 
	assert results[3][0] == 11 
	query.close()

	qstr = r'declare variable $msg external; 
					<el>{$msg}</el>'
	query = session.new_query(qstr)!
	query.bind('msg', 'hello binding', '')!
	isupdating := query.updating()
	assert !isupdating 
	
	response = query.execute()!.bytestr()
	assert response == '<el>hello binding</el>'
	query.close()

	qstr = r'for $val in ("a", "b")
						return ($val)' 
	query = session.new_query(qstr)!
	query.execute_iterate()
	if val := query.next() {
		assert val.bytestr() == 'a'
	}
	if val := query.next() {
		assert val.bytestr() == 'b'
	}
}
