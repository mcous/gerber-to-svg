# test suit for the NC drill file parser
Parser = require '../src/drill-parser'

describe 'NC drill file parser', ->
  p = null
  beforeEach -> p = new Parser

  it "should ignore comments (start with ';')", ->
    initialFmat = p.fmat
    initialFormat = { zero: p.format.zero, places: p.format.places }
    p.parseCommand(';INCH').should.eql {}
    p.parseCommand(';M71').should.eql {}
    p.parseCommand(';T1C0.015').should.eql {}
    p.parseCommand(';T1').should.eql {}
    p.parseCommand(';X0016Y0158').should.eql {}
    p.parseCommand(';INCH,TZ').should.eql {}
    p.fmat.should.eql initialFmat
    p.format.should.eql initialFormat
  it 'should return a done command with M00 or M30', ->
    p.parseCommand('M00').should.eql { set: { done: true } }
    p.parseCommand('M30').should.eql { set: { done: true } }
  it 'should return a set units command with INCH and METRIC', ->
    p.parseCommand('INCH').should.eql { set: { units: 'in' } }
    p.parseCommand('METRIC').should.eql { set: { units: 'mm' } }
  it 'should also set units with M71 and M72', ->
    p.parseCommand('M71').should.eql { set: { units: 'mm' } }
    p.parseCommand('M72').should.eql { set: { units: 'in' } }
  it 'should be able to set the zero suppression', ->
    # excellon specifies which zeros to keep
    # also check that whitespace doesn't throw it off
    p.parseCommand 'INCH,TZ'
    p.format.zero.should.eql 'L'
    p.parseCommand 'INCH,LZ'
    p.format.zero.should.eql 'T'
    p.parseCommand 'INCH,TZ'
    p.format.zero.should.eql 'L'
    p.parseCommand 'INCH,LZ'
    p.format.zero.should.eql 'T'
  it 'should warn and fall back to leading suppression if unspecified', ->
    p.format.places = [2,4]
    # have a backup
    p.format.zero?.should.not.be.true
    hook = require('./stream-capture')(process.stderr)
    p.parseCommand 'X50Y15500'
    p.format.zero.should.eql 'L'
    hook.captured().should.match /assuming leading zero suppression/
    hook.unhook()
  it 'should warn and fall back to 2:4 format if unspecified', ->
    p.format.zero = 'L'
    p.format.places?.should.not.be.true
    hook = require('./stream-capture')(process.stderr)
    p.parseCommand 'X50Y15500'
    p.format.places.should.eql [ 2, 4 ]
    hook.captured().should.match /assuming 2\:4/
    hook.unhook()
  it 'should use 3.3 format for metric and 2.4 for inches', ->
    p.parseCommand 'INCH'
    p.format.places.should.eql [ 2, 4 ]
    p.parseCommand 'METRIC'
    p.format.places.should.eql [ 3, 3 ]
  describe 'tool definitions', ->
    beforeEach ->
      p.format.zero = 'L'
      p.format.places = [ 2, 4 ]
    it 'should return a define tool command for tool definitions', ->
      p.parseCommand 'T1C0.015'
        .should.eql { tool: { T1: { dia: 150 } } }
      p.parseCommand 'T13C0.142'
        .should.eql { tool: { T13: { dia: 1420 } } }
    it 'should ignore feedrate and spindle speed', ->
      p.parseCommand 'T1C0.01F100S5'
        .should.eql { tool: { T1: { dia: 100 } } }
    it 'should ignore leading zeros in tool name', ->
      p.parseCommand 'T01C0.015'
        .should.eql { tool: { T1: { dia: 150 } } }
  it 'should assume FMAT,2, but identify FMAT,1', ->
    p.fmat.should.eql 'FMAT,2'
    p.parseCommand('FMAT,1').should.eql {}
    p.fmat.should.eql 'FMAT,1'
    p.parseCommand('M70').should.eql { set: { units: 'in' } }
  it 'should return a set tool for a bare tool number', ->
    p.parseCommand('T1').should.eql { set: { currentTool: 'T1' } }
    p.parseCommand('T14').should.eql { set: { currentTool: 'T14' } }
  it 'should ignore leading zeros in tool name', ->
    p.parseCommand('T01').should.eql { set: { currentTool: 'T1' } }
  it 'should return a set notation to abs with G90', ->
    p.parseCommand('G90').should.eql { set: { notation: 'abs' } }
  it 'should return a set notation to inc with G91', ->
    p.parseCommand('G91').should.eql { set: { notation: 'inc' } }
  it 'M70 (fmat1), M71, and M72 should still set units', ->
    p.parseCommand('M71').should.eql { set: { units: 'mm' } }
    p.parseCommand('M72').should.eql { set: { units: 'in' } }
    p.fmat = 'FMAT,1'
    p.parseCommand('M70').should.eql { set: { units: 'in' } }

  describe 'drilling (flashing) at coordinates', ->
    it 'should parse the coordinates into numbers in suppress trailing zero', ->
      p.format.zero = 'T'
      p.format.places = [2,4]
      p.parseCommand('X0016Y0158').should.eql {
        op: { do: 'flash', x: 1600, y: 15800 }
      }
      p.parseCommand('X-01795Y0108').should.eql {
        op: { do: 'flash', x: -17950, y: 10800 }
      }
    it 'should parse coordinates with leading zeros suppressed', ->
      p.format.zero = 'L'
      p.format.places = [2,4]
      p.parseCommand('X50Y15500').should.eql {
        op: { do: 'flash', x: 50, y: 15500 }
      }
      p.parseCommand('X16850Y-3300').should.eql {
        op: { do: 'flash', x: 16850, y: -3300 }
      }
    it 'should parse coordinates according to the places format', ->
      p.format.zero = 'L'
      p.format.places = [2,4]
      p.parseCommand('X7550Y14000').should.eql {
        op: { do: 'flash', x: 7550, y: 14000 }
      }
      p.format.places = [3,3]
      p.parseCommand('X7550Y14').should.eql {
        op: { do: 'flash', x: 7550, y: 14 }
      }
      p.format.zero = 'T'
      p.format.places = [2,4]
      p.parseCommand('X08Y0124').should.eql {
        op: { do: 'flash', x: 80000, y: 12400 }
      }
      p.format.places = [3,3]
      p.parseCommand('X08Y0124').should.eql {
        op: { do: 'flash', x: 80000, y: 12400 }
      }
    it 'should parse decimal coordinates', ->
      p.format.zero = 'L'
      p.format.places = [2,4]
      p.parseCommand('X0.7550Y1.4000').should.eql {
        op: { do: 'flash', x: 7550, y: 14000 }
      }
      p.format.places = [3,3]
      p.parseCommand('X7.550Y14').should.eql {
        op: { do: 'flash', x: 7550, y: 14 }
      }
    it 'should recognize a tool change at the beginning or end of the line', ->
      p.format.zero = 'T'
      p.format.places = [2,4]
      p.parseCommand('T01X01Y01').should.eql {
        set: { currentTool: 'T1' }, op: { do: 'flash', x: 10000, y: 10000 }
      }
      p.parseCommand('X01Y01T01').should.eql {
        set: { currentTool: 'T1' }, op: { do: 'flash', x: 10000, y: 10000 }
      }
      