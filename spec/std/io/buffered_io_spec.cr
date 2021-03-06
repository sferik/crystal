require "spec"

class BufferedIOWrapper(T)
  include BufferedIO

  getter called_unbuffered_read

  def initialize(@io : T)
    @in_buffer_rem = Slice.new(Pointer(UInt8).null, 0)
    @out_count = 0
    @flush_on_newline = false
    @sync = false
    @called_unbuffered_read = false
  end

  def self.new(io)
    buffered_io = new(io)
    yield buffered_io
    buffered_io.flush
    io
  end

  private def unbuffered_read(slice : Slice(UInt8))
    @called_unbuffered_read = true
    @io.read(slice)
  end

  private def unbuffered_write(slice : Slice(UInt8))
    @io.write(slice)
  end

  private def unbuffered_flush
    @io.flush
  end

  def fd
    @io.fd
  end

  private def unbuffered_close
    @io.close
  end

  def closed?
    @io.closed?
  end

  def to_fd_io
    @io.to_fd_io
  end

  private def unbuffered_rewind
    @io.rewind
  end
end

describe "BufferedIO" do
  it "does gets" do
    io = BufferedIOWrapper.new(StringIO.new("hello\nworld\n"))
    io.gets.should eq("hello\n")
    io.gets.should eq("world\n")
    io.gets.should be_nil
  end

  it "does gets with big line" do
    big_line = "a" * 20_000
    io = BufferedIOWrapper.new(StringIO.new("#{big_line}\nworld\n"))
    io.gets.should eq("#{big_line}\n")
  end

  it "does gets with char delimiter" do
    io = BufferedIOWrapper.new(StringIO.new("hello world"))
    io.gets('w').should eq("hello w")
    io.gets('r').should eq("or")
    io.gets('r').should eq("ld")
    io.gets('r').should be_nil
  end

  it "does gets with unicode char delimiter" do
    io = BufferedIOWrapper.new(StringIO.new("こんにちは"))
    io.gets('ち').should eq("こんにち")
    io.gets('ち').should eq("は")
    io.gets('ち').should be_nil
  end

  it "does gets with limit" do
    io = BufferedIOWrapper.new(StringIO.new("hello\nworld\n"))
    io.gets(3).should eq("hel")
    io.gets(10_000).should eq("lo\n")
    io.gets(10_000).should eq("world\n")
    io.gets(3).should be_nil
  end

  it "does gets with char and limit" do
    io = BufferedIOWrapper.new(StringIO.new("hello\nworld\n"))
    io.gets('o', 2).should eq("he")
    io.gets('w', 10_000).should eq("llo\nw")
    io.gets('z', 10_000).should eq("orld\n")
    io.gets('a', 3).should be_nil
  end

  it "does gets with char and limit when not found in buffer" do
    io = BufferedIOWrapper.new(StringIO.new(("a" * (BufferedIO::BUFFER_SIZE + 10)) + "b"))
    io.gets('b', 2).should eq("aa")
  end

  it "does gets with char and limit when not found in buffer (2)" do
    base = "a" * (BufferedIO::BUFFER_SIZE + 10)
    io = BufferedIOWrapper.new(StringIO.new(base + "aabaaa"))
    io.gets('b', BufferedIO::BUFFER_SIZE + 11).should eq(base + "a")
  end

  it "raises if invoking gets with negative limit" do
    io = BufferedIOWrapper.new(StringIO.new("hello\nworld\n"))
    expect_raises ArgumentError, "negative limit" do
      io.gets(-1)
    end
  end

  it "writes bytes" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    10_000.times { io.write_byte 'a'.ord.to_u8 }
    io.flush
    str.to_s.should eq("a" * 10_000)
  end

  it "reads char" do
    io = BufferedIOWrapper.new(StringIO.new("hi 世界"))
    io.read_char.should eq('h')
    io.read_char.should eq('i')
    io.read_char.should eq(' ')
    io.read_char.should eq('世')
    io.read_char.should eq('界')
    io.read_char.should be_nil
  end

  it "reads byte" do
    io = BufferedIOWrapper.new(StringIO.new("hello"))
    io.read_byte.should eq('h'.ord)
    io.read_byte.should eq('e'.ord)
    io.read_byte.should eq('l'.ord)
    io.read_byte.should eq('l'.ord)
    io.read_byte.should eq('o'.ord)
    io.read_char.should be_nil
  end

  it "does new with block" do
    str = StringIO.new
    res = BufferedIOWrapper.new str, &.print "Hello"
    res.should be(str)
    str.to_s.should eq("Hello")
  end

  it "rewinds" do
    str = StringIO.new("hello\nworld\n")
    io = BufferedIOWrapper.new str
    io.gets.should eq("hello\n")
    io.rewind
    io.gets.should eq("hello\n")
  end

  it "reads more than the buffer's internal capacity" do
    s = String.build do |str|
      900.times do
        10.times do |i|
          str << ('a'.ord + i).chr
        end
      end
    end
    io = BufferedIOWrapper.new(StringIO.new(s))

    slice = Slice(UInt8).new(9000)
    count = io.read(slice)
    count.should eq(9000)

    900.times do
      10.times do |i|
        slice[i].should eq('a'.ord + i)
      end
    end
  end

  it "does read with limit" do
    io = BufferedIOWrapper.new(StringIO.new("hello world"))
    io.read(5).should eq("hello")
    io.read(10).should eq(" world")
    io.read(5).should eq("")
  end

  it "raises argument error if reads negative length" do
    io = BufferedIOWrapper.new(StringIO.new("hello world"))
    expect_raises(ArgumentError, "negative length") do
      io.read(-1)
    end
  end

  it "does puts" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    io.puts "Hello"
    str.to_s.should eq("")
    io.flush
    str.to_s.should eq("Hello\n")
  end

  it "does puts with big string" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    s = "*" * 20_000
    io << "hello"
    io << s
    io.flush
    str.to_s.should eq("hello#{s}")
  end

  it "does puts many times" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    10_000.times { io << "hello" }
    io.flush
    str.to_s.should eq("hello" * 10_000)
  end

  it "flushes on \n" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    io.flush_on_newline = true

    io << "hello\nworld"
    str.to_s.should eq("hello\n")
    io.flush
    str.to_s.should eq("hello\nworld")
  end

  it "doesn't write past count" do
    str = StringIO.new
    io = BufferedIOWrapper.new(str)
    io.flush_on_newline = true

    slice = Slice.new(10) { |i| i == 9 ? '\n'.ord.to_u8 : ('a'.ord + i).to_u8 }
    io.write slice[0, 4]
    io.flush
    str.to_s.should eq("abcd")
  end

  it "syncs" do
    str = StringIO.new

    io = BufferedIOWrapper.new(str)
    io.sync?.should be_false

    io.sync = true
    io.sync?.should be_true

    io.write_byte 1_u8

    str.rewind
    str.read_byte.should eq(1_u8)
  end

  it "shouldn't call unbuffered read if reading to an empty slice" do
    str = StringIO.new("foo")
    io = BufferedIOWrapper.new(str)
    io.read(Slice(UInt8).new(0))
    io.called_unbuffered_read.should be_false
  end
end
