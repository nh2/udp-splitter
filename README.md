# udp-splitter

Haskell program to forward incoming UDP packets to N many targets


## Compile

With [stack](https://haskellstack.org):

```
stack script --resolver lts-9.6 --optimize udp-splitter.hs
```


## Example

We use `socat` for UPD listening because `nc` has lots of [weirdnesses](https://stackoverflow.com/questions/7696862/strange-behavoiur-of-netcat-with-udp) when dealing with UDP.

In terminal 1, listen to an IPv4 port:

```
socat UDP-RECV:8004 STDOUT
```

In terminal 2, listen to an IPv6 port:

```
socat UDP6-RECV:8006 STDOUT
```

In terminal 3, start the splitter:

```
./udp-splitter localhost:8000 127.0.0.1:8004 ::1:8006
```

In terminal 4, send something to the splitter:

```
echo hello | nc -u localhost 8000
```

The output `hello` should appear in terminals 1 and 2.
