V-BaseX
=======

This is a BaseX client library for the V programming language. See https://vlang.io 

The V language is most like golang with several improvements, although not mature as yet.
V is simple to learn but has a number of limitations, like go, compared to
more concept rich languages like Rust, Scala, Python, etc. It's not an object oriented 
or functional programming language. V is its own thing. I like it!

BaseX is a great little XML database. Its easy to develop with, deploy, and maintain.
It's fast and flexible. It allows storage of xml, json, csv, and binaries. It's easy
to integrate 3rd party Java libraries.

The V-BaseX library implements 'most' of the Basex API and has about 30 tests to learn how
to use it. The library is NOT production ready. The library  was implemented to try out 
the V language. It's not idiomatic or consistant V as I was experiementing with different 
features of the language. If there is interest, and time permitting, I'll continue to improve
and bug fix. Suggestions and contributions welcome.

MIT License

V language version:   0.3.2,  Basex version:        10.3

BaseX Setup:
See https://basex.org/ 
run './basexhttp -c password'
Use admin for password in test.


V Setup:
See https://vlang.io 


I like running tests during development using 'entr' so tests are rerun after making a source code change.
>find . -name '*.v' | entr -cr v -stats -cg test basex/basex_test.v

Example Usage: 
In BaseX, create a user test/test with admin permissions

```
import eptx.basex

fn main() {
	mut session := basex.create('127.0.0.1', 1984, 'test', 'test') or {panic('No Session')}
	session.execute('create database testdb <hello_test/>')!
	mut response, mut info := session.execute('list')!
	println(response)
	assert response.contains('testdb')
	assert response.contains('testdb.xml')

	session.execute('drop database testdb')!
	response, info = session.execute('list')!
	println(response)
	assert !response.contains('testdb')
}

```
