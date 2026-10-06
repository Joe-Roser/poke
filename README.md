A reminder daemon because I get too zoned in to work

Interact with the poke command.

# Installation
Install with the install.sh script.
Requirements: zig
This will build the executables, copy them to '.local/bin/poke', and install the poke.service file to .config/systemd/user/poke.service.
Any deviations from the norm will have to install manually.

# Poke Commands
- work - Start the work timer
- break - Start the break timer
- ack - Acknoledge a notification
- stop - Stop the timers
- quit - Close poke
- inspect - See poke state

# Thanks
Thanks to [luxluth](https://github.com/luxluth) for making the [goose](https://github.com/luxluth/goose) library which has been slightly modified for use here.
