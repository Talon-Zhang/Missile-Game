
# mp1.S - missile-command version
# Good luck, and have fun!


.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64

	#self_defined data
	x_bound=79
	y_bound=24

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	# (1) update the list of missiles
 	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    call update_missiles   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	# (2) draw the three bases
 	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    call redraw_cities   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	# (3) redraw the crosshair
 	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    call redraw_crosshair   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
	movl 8(%esp), %ecx	#ecx stores cmd
	mov $0, %edx
	cmpl %edx,%ecx
	jl dispatcher_ret	#if cmd<0, return
	mov $4, %edx
	cmpl %edx,%ecx
	jg dispatcher_ret	#if cmd>4, return
	jmp *jumptable(,%ecx,4)	#jump to the corresponding function
dispatcher_ret:
	mov $-1, %eax
	ret
# ----------------- Functions private to this file -------------------

#void update_missiles();
update_missiles:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	mov mp1_missile_list, %ecx	#ecx is used tp traverse the link list
update_loop:
	cmpl $0,%ecx
	je list_finish	#if the current address is 0, finish traverse
	movl NEXT(%ecx),%ebx	#ebx stores the location of next missile
	#1. remove the missile from the screen
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    movl X(%ecx),%edi
	shrl $16,%edi	#get the screen coordiante
	movl Y(%ecx),%esi
	shrl $16,%esi	
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	movl %esi,%eax
	movb $32,%cl	#32 is the ascii number of space
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	#2. check xy bounds
	movl X(%ecx),%edi	#edi stores next location of x
	addl VX(%ecx),%edi
	shrl $16,%edi
	movl Y(%ecx),%esi	#esi stores next location of y
	addl VY(%ecx),%esi
	shrl $16,%esi
	cmp $0,%edi
	jl update_erase_missile	
	cmp $x_bound,%edi
	jg update_erase_missile
	cmp $0,%esi
	jl update_erase_missile
	cmp $y_bound,%esi
	jg update_erase_missile
	#3. check explodsion
	#check if missile reaches destination
	movl X(%ecx),%edi	#edi stores next location of x
	#addl VX(%ecx),%edi
	shrl $16,%edi
	movl Y(%ecx),%esi	#esi stores next location of y
	#addl VY(%ecx),%esi
	shrl $16,%esi
	cmpl DEST_X(%ecx),%edi
	jne check_currently_exploding
	cmpl DEST_Y(%ecx),%esi
	jne check_currently_exploding
	jmp call_missile_explode
check_currently_exploding:
	cmpl $0,EXPLODED(%ecx)
	je update_position
call_missile_explode:
    pushl %ecx	#save caller-saved registers 
    pushl %edx
    pushl %ecx	#push arguments onto stack 
    call missile_explode   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
	cmpl $0,%eax
	je not_notify_user
	#notify user
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    call mp1_notify_user   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
not_notify_user:
	decl EXPLODED(%ecx)
	movl EXPLODED(%ecx),%edi
	cmpl $0,%edi
	jne draw_exploded_missile
	#free the missile
  	jmp update_erase_missile
draw_exploded_missile:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    movl X(%ecx),%edi
	shrl $16,%edi	#find x, y coordinate
	movl Y(%ecx),%esi
	shrl $16,%esi
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	movl %esi,%eax
	movb $EXPLOSION,%cl	
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp update_next_missile
update_position:
	#4. simply move missile to next position
	movl X(%ecx),%edi	#edi stores next location of x
	addl VX(%ecx),%edi
	movl %edi,X(%ecx)
	movl Y(%ecx),%esi	#esi stores next location of y
	addl VY(%ecx),%esi
	movl %esi,Y(%ecx)
redraw_missile:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    movl X(%ecx),%edi
	shrl $16,%edi	#find x, y coordinate
	movl Y(%ecx),%esi
	shrl $16,%esi
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	movl %esi,%eax
	movb C(%ecx),%cl	
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp update_next_missile
update_erase_missile:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl %ecx	#push arguments onto stack 
    call mp1_missile_remove   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
update_next_missile:
	mov %ebx,%ecx	#move to next missile
	jmp update_loop
list_finish:
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#void mp1_missile_remove(void* missile_location)
mp1_missile_remove:
    pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp), %ecx	#ecx stores the address of the missile to remove from link list
	#start function body
	#check if the address is head
	cmpl mp1_missile_list,%ecx
	jne remove_not_head
	movl NEXT(%ecx),%edx
	movl %edx,mp1_missile_list
remove_not_head:
	movl mp1_missile_list,%edx	#we use edx to traverse the link list to find the last struct
remove_loop:	
	movl NEXT(%edx),%ebx	#ebx stores address the next struct
	cmpl %ebx,%ecx
	je remove_from_list
	movl NEXT(%edx),%edx
	cmpl $0,%edx
	je remove_finish
	jmp remove_loop
remove_from_list:
	movl NEXT(%ecx),%edi	
	movl %edi, NEXT(%edx)
remove_free_missile:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl %ecx	#push arguments onto stack 
    call mp1_free   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
remove_finish:
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#void redraw_cities(void)
redraw_cities:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	movl $base_alive,%ecx
	cmpb $0,0(%ecx) 
	je first_base_die
	#first base alive
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $18	#x position for first base
	pushl $base_pic 
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp draw_second_base
first_base_die:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $18	#x position for first base
	pushl $dead_base_pic
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
draw_second_base:
	cmpb $0,1(%ecx) 
	je second_base_die
	#second base alive
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $38	#x position for second base
	pushl $base_pic 
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp draw_third_base
second_base_die:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $38	#x position for second base
	pushl $dead_base_pic
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
draw_third_base:
	cmpb $0,2(%ecx) 
	je third_base_die
	#third base alive
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $58	#x position for third base
	pushl $base_pic 
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp finish_draw_base
third_base_die:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl $58	#x position for third base
	pushl $dead_base_pic
    call redraw_cities_help   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
finish_draw_base:
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#void redraw_cities_help(void* character, int start_position)
redraw_cities_help:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp), %ecx	#the address of the five character string to draw
	movl 12(%ebp), %edx	#the x_position to start drawing
	#start function body
	movl $5,%ebx	#there are five characters to draw
draw_loop:
	cmpl $0,%ebx
	je finish_draw
	#draw the character
	pushl %eax  #save caller-saved registers 
    pushl %ecx
	pushl %edx
    movl %edx,%edi	#x_position
	movl $24,%esi	#y_position
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	movl %esi,%eax
    movb (%ecx),%cl
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	#update parameters
	decl %ebx	#next character
	incl %ecx	#next character's position
	incl %edx	#next x position
	jmp draw_loop
finish_draw:
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret
	
#void redraw_crosshair(void)	
redraw_crosshair:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
	pushl $2	#the cmd for drawing crosshair is 2
    pushl $0	#push arguments onto stack 
    call mp1_ioctl   #make the call
    addl $8,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#int mp1 ioctl startgame (unsigned long ignore);
mp1_ioctl_startgame:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	movl $0, mp1_missile_list	#initialization
	movl $0x00010101, base_alive
	movl $0, mp1_score
	movl $40, crosshairs_x
	movl $12, crosshairs_y
	#finish function body
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#int mp1 ioctl addmissile (struct missile* user missile);
mp1_ioctl_addmissile:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp), %ecx	#ecx stores the address of struct
	#start function body
	#allocate memory		 
    pushl %ecx	 #save caller-saved registers
    pushl %edx
    pushl $33	#push arguments onto stack(the struct size)
    call mp1_malloc   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
	cmpl $0, %eax
	je add_missile_fail #if malloc fails, return -1
	movl %eax, %edx	#edx stores the allocated memory address
	#copy from user   
    pushl %ecx	#save caller-saved registers
    pushl %edx
    pushl $33		#push arguments onto stack(the struct size)
	pushl %ecx
	pushl %edx
    call mp1_copy_from_user   #make the call
    addl $12,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    cmpl $0, %eax
	je add_to_link_list
	#copy from user fails
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl %edx	#push arguments onto stack 
    call mp1_free   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp add_missile_fail
add_to_link_list:
	movl mp1_missile_list,%ebx
	movl %ebx,NEXT(%edx) 
	movl %edx,mp1_missile_list
	jmp add_missile_finish
	#finish function body
add_missile_fail:
	movl $-1, %eax
add_missile_finish:
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#int mp1 ioctl movexhairs (unsigned long xhair delta packed);
mp1_ioctl_movexhairs:
	pushl %ebp	#set up stack frame
	movl %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movw 8(%ebp),%cx	
	movswl %cx,%ecx	#ecx contains the x component
	movw 10(%ebp),%dx
	movswl %dx,%edx	#edx contains the y component
	#start function body
	cmpl $0,%ecx	#check if the position changes
	je remove_crosshair
	cmpl $0,%edx
	je remove_crosshair
	jmp finish_movexhairs
remove_crosshair:
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    movl crosshairs_x,%edi
	movl crosshairs_y,%esi
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	mov	%esi,%eax
	movb $32,%cl	#32 is the ascii number of space
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
#check bounds
	addl crosshairs_x,%ecx
	cmpl $0,%ecx
	jl xhair_zero_x
	cmpl $x_bound,%ecx
	jg xhair_max_x
	jmp xhair_check_y
xhair_zero_x:
	movl $0,%ecx
	jmp xhair_check_y
xhair_max_x:
	movl $x_bound,%ecx
xhair_check_y:
	addl crosshairs_y,%edx
	cmpl $0,%edx
	jl xhair_zero_y
	cmpl $y_bound,%edx
	jg xhair_max_y
	jmp xhair_update_xy
xhair_zero_y:
	movl $0,%edx
	jmp xhair_update_xy
xhair_max_y:
	movl $y_bound,%edx
xhair_update_xy:
	movl %ecx,crosshairs_x
	movl %edx,crosshairs_y
#draw the new cross_hair
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    movl crosshairs_x,%edi
	movl crosshairs_y,%esi
	imul $160,%esi,%esi 	#claculate the screen coordiante(y*160+x*2)
	imul $2,%edi,%edi 
	addl %edi,%esi
	mov	%esi,%eax
	movb $43,%cl	#43 is the ascii number of "+"
    call mp1_poke   #make the call
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
finish_movexhairs:
	#finish function body
	movl $0, %eax
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#int mp1 ioctl getstatus (unsigned long* user status);
mp1_ioctl_getstatus:
	pushl %ebp	#set up stack frame
	movl %esp,%ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl 8(%ebp),%ecx	#ecx stores the memory in user space
	#start function body
	xorl %edx,%edx	#edx is used to store the 18 bits status
	#push base_status into edx
	movl $base_alive,%ebx	#ebx is the address of base_alive
	cmpb $0,0(%ebx)
	je status_second_base
	addl $1,%edx	#first base is 1, corresponding to the 16th bit
status_second_base:
	cmpb $0,1(%ebx)
	je status_third_base
	addl $2,%edx	#second base is 1, corresponding to the 17th bit
status_third_base:
	cmpb $0,2(%ebx)
	je shift_to_high
	addl $4,%edx	#third base is 1, corresponding to the 18th bit
shift_to_high:
	shll $16,%edx
	#push score into dx, the lower 16 bits
	movw mp1_score,%dx	
	#allocate memory		 
    pushl %ecx	 #save caller-saved registers 
    pushl %edx
    pushl $4	#push arguments onto stack 
    call mp1_malloc   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
	cmpl $0,%eax
	je get_status_fail #if malloc fails, return -1
	movl %eax,%edi	#edi has the allocated memory address
	movl %edx,(%edi)	#push status code into the allocated memory
	#copy to user   
    pushl %ecx	#save caller-saved registers
    pushl %edx
    pushl $4	#push arguments onto stack 
	pushl %edi
	pushl %ecx
    call mp1_copy_to_user   #make the call
    addl $12,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    cmpl $0, %eax
	je get_status_success
	#copy to user fails
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl %edi	#push arguments onto stack 
    call mp1_free   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	jmp get_status_fail
get_status_success:
	movl $0,%eax
	jmp get_status_finish
get_status_fail:
	movl $-1,%eax
	#finish function body
get_status_finish:
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

#int mp1 ioctl endgame (unsigned long ignore);
mp1_ioctl_endgame:
	pushl %ebp	#set up stack frame
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	#start function body
	movl mp1_missile_list, %ecx
endgame_stack_loop:
	cmp $0,%ecx
	je endgame_finish
	movl NEXT(%ecx),%ebx
	#free the current struct address
	pushl %eax  #save caller-saved registers 
    pushl %ecx
    pushl %edx
    pushl %ecx	#push arguments onto stack 
    call mp1_free   #make the call
    addl $4,%esp	#pop arguments off the stack
    popl %edx   #restore caller-saved registers
    popl %ecx
    popl %eax
	movl %ebx,%ecx
	jmp endgame_stack_loop
	#finish function body
endgame_finish:
	popl %edi	#tear down stack frame
	popl %esi
	popl %ebx
	leave
	ret

jumptable:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame