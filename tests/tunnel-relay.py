"""Stand-in for what sshd does with a RemoteForward: publish a loopback port on
the machine running the agent and splice every connection through to the Unix
socket the daemon is listening on. The tests need that link without needing an
ssh server, a second machine, or credentials.

Usage: python3 tunnel-relay.py <port> <socket path>
Port 0 takes whatever is free, which is what keeps a test from colliding with a
real tunnel on the machine running it. The port it settled on is printed as
"ready <port>" once it is accepting, so a test can wait for that line and read
the number out of it.
"""

import socket
import sys
import threading

port = int(sys.argv[1])
socket_path = sys.argv[2]

listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", port))
listener.listen(16)


def pump(source, sink):
    try:
        while True:
            chunk = source.recv(4096)
            if not chunk:
                break
            sink.sendall(chunk)
    except OSError:
        pass
    finally:
        # Half-close rather than close: the far side has to see the end of file,
        # since the close is the message that a turn is over. Closing here would
        # free the descriptor while the other direction's thread is still sitting
        # on it, and the next connection to take that number would be spliced
        # into the wrong conversation.
        try:
            sink.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def splice(client):
    upstream = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        upstream.connect(socket_path)
    except OSError:
        client.close()
        return
    outbound = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    outbound.start()
    pump(upstream, client)
    # Both directions are finished with both descriptors before either is freed.
    outbound.join()
    client.close()
    upstream.close()


print("ready %d" % listener.getsockname()[1], flush=True)
while True:
    connection, _ = listener.accept()
    threading.Thread(target=splice, args=(connection,), daemon=True).start()
