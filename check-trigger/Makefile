CC      = gcc
CFLAGS  = -Wall
LD      = gcc
LDFLAGS = 
OBJS    = main.o
LIBS    =

.c.o:
	$(CC) -c -o $*.o $<

check-trigger: $(OBJS)
	$(LD) -o $@ $(OBJS) $(LIBS)

$(OBJS): Makefile

main.o: main.c
 
clean:
	rm -f $(OBJS) *~
