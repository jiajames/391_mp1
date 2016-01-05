
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

    # Character to draw for an explosion: '@'; empty: ' '; crosshair: '+'

    EMPTY     = 32
    CROSSHAIR = 43
	EXPLOSION = 64


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

base_1:				.long 0xF24	    # start of base 1 location on screen (18,24), (24*160) + (18*2), 3876(dec)
base_2:             .long 0xF4C     # (38,24), (24*160) + (38*2), 3916(dec)
base_3:				.long 0xF74	

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

	pushl %ebp
	movl %esp, %ebp
	pushl %esp
	pushl %edi
	pushl %esi
	pushl %ebx

	// step 1: update missiles
	call update_missiles
	// step 2: update cities
	call update_cities
	// step 3: update crosshairs 
	call update_crosshairs

	popl %ebx
	popl %esi
	popl %edi
	popl %esp

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

	// validates input, does not run if invalid. If it is valid, use jump table for correcct function
	// invalid inputs: input > 4 or input < 0
	cmpl $4,8(%esp)
	ja bad_input
	movl 8(%esp),%eax
	jmp *jump_table(,%eax,4)

bad_input:	
	
	movl $-1,%eax
	ret

jump_table:
		.long	mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file ------------------- #

# void update_missiles()
# This function updates all missiles that are within the linked list,
# including the update of the location on the screen, the character drawn
# and removes missiles when they are off the screen or done exploding 
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

update_missiles:

	// save register values onto the stack, as well as pointer to
	// the first missile pointer (so it fits our implementation)
	pushl %ebp
	movl %esp, %ebp
	pushl $mp1_missile_list
	pushl %edx
	pushl %ecx
	pushl %ebx

check_next_missile:
	
	// checks if there is a next missile to check, exits if none
	movl -4(%ebp), %ebx
	movl NEXT(%ebx), %ebx
	cmpl $0, %ebx
	je exit_update_missile

	// clears missile from old location (if doesn't move, still clears)
	movl $EMPTY, %ecx
	call draw_missile	

	// checks if the missile is currently exploading
	cmpl $0, EXPLODED(%ebx)
	jne check_missile_explode

	// updates Y and X locations, checks for out of bounds
	movl Y(%ebx), %eax
	addl VY(%ebx), %eax
	roll $16, %eax
	cmpw $24, %ax
	ja remove_missile
	cmpw $0, %ax
	jb remove_missile
	roll $16, %eax
	movl %eax, Y(%ebx)

	movl X(%ebx), %eax
	addl VX(%ebx), %eax
	roll $16, %eax
	cmpw $79, %ax
	ja remove_missile
	cmpw $0, %ax
	jb remove_missile
	roll $16, %eax
	movl %eax, X(%ebx)

	// checks if missile is at destination
	movl Y(%ebx), %eax
	shrl $16, %eax
	cmpl %eax, DEST_Y(%ebx)
	jne  missile_not_at_destination
	movl X(%ebx), %eax
	shrl $16, %eax
	cmpl %eax, DEST_X(%ebx)
	jne  missile_not_at_destination

check_missile_explode:

	// missile is exploding if enters this subroutine
	// call missile explode, notify user if any cities updated
	// or any other missiles are exploded due to ours
	// and notifies accordingly
	pushl %ebx
	call missile_explode
	cmpl $0, %eax
	je no_notify_user
	call mp1_notify_user

no_notify_user:

	// decrements exploded counter, and removes the missile if finished exploding
	// also draws the missile if it is still exploding
	// when finished drawing, get the pointer to next missile and check
	decl EXPLODED(%ebx)
	cmpl $0, EXPLODED(%ebx)
	je remove_missile
	movl $EXPLOSION, %ecx
	call draw_missile
	movl %ebx, -4(%ebp)
	jmp check_next_missile

missile_not_at_destination:

	// if in this subroutine, missile is currently travelling on the screen
	// and needs a redraw. after finished drawing, get the pointer to next missile and check
	movl C(%ebx), %ecx
	call draw_missile
	movl %ebx, -4(%ebp)
	jmp check_next_missile

remove_missile:

	// if in this subroutine, missile needs to be removed
	// call mp1_missile_remove and pop off the stack
	// and move to the next missile
	pushl -4(%ebp)
	call mp1_missile_remove
	addl $4, %esp
	jmp check_next_missile

exit_update_missile:

	// restore the stack after all missiles have been updated
	popl %ebx
	popl %ecx
	popl %edx
	leave
	ret

# void mp1_missile_remove(unsigned long * missile)
# removes the current missile from the linked list of missiles
# and frees the missile structure from memory
# Inputs   : unsigned long * missile - pointer to current missile to remove from memory
# Outputs  : none
# Registers: Standard C calling convention

mp1_missile_remove:

	// prev_pointer->next = curr_pointer->next
	// free curr_pointer
	pushl %ebp
	movl %esp, %ebp
	movl 8(%ebp), %eax
	movl NEXT(%eax), %ebx
	pushl %ebx
	movl NEXT(%ebx), %ebx
	movl %ebx, NEXT(%eax)
	call mp1_free
	leave
	ret

# void draw_missile()
# wrapper function to prepare registers 
# %eax (video memory location)
# %cl (character to draw) 
# for mp1_poke call
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

draw_missile:

	// to find video location:
	// (Y_value * 80 * 2) + (X_value * 2) -> %eax
	pushl %ebp
	movl %esp, %ebp
	push %edx
	movl Y(%ebx), %eax
	shrl $16, %eax
	imull $160, %eax
	movl X(%ebx), %edx
	shrl $16, %edx
	imull $2, %edx
	addl %edx, %eax
	call mp1_poke
	popl %edx
	leave
	ret

# void update_cities()
# redraws the bases based on if they are alive or not
# which is given in the arraw at base_alive
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

update_cities:

	// base_1, base_2, and base_3 contain the corresponding
	// video memory locations, save in memory
	pushl %ebp
	movl %esp, %ebp
	movl base_alive, %eax
	pushl base_1
	call print_base
	shrl $8, %eax
	pushl base_2
	call print_base
	shrl $8, %eax
	pushl base_3
	call print_base
	addl $12, %esp

	leave
	ret

print_base:

	// prints current base, where %eax
	// contains the byte that is non-zero(alive) or zero (dead)
	// uses a counter of 5 to print each of the 5 characters in the string
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %eax
	pushl $5
	cmpb $0, %al
	je print_base_dead

	// if it reaches this, then current base is alive
	// put alive base string into ebx to draw
	movl $base_pic, %ebx
	jmp print_base_1

print_base_dead:

	// if it reaches this, then current base is dead
	// put dead base string into ebx to draw
	movl $dead_base_pic, %ebx

print_base_1:

	// calls mp1_poke to draw character onto screen
	// iterates through base string to draw, exits
	// loops 5 times before it exits
	movb (%ebx), %cl
	movl 8(%ebp), %eax
	call mp1_poke
	addl $2, 8(%ebp)
	incl %ebx
	decl -12(%ebp)
	jne print_base_1
	addl $4, %esp
	popl %eax
	popl %ebx
	leave
	ret

# void update_crosshairs()
# after missiles and cities have been drawn, 
# redraw crosshair so that it is always showing
# Inputs   : non
# Outputs  : none
# Registers: Standard C calling convention

update_crosshairs:

	// same convention as drawing a missile
	pushl %ebp
	movl %esp, %ebp
	imull $160, crosshairs_y, %eax
	imull $2, crosshairs_x, %edx
	addl %edx, %eax
	movl $CROSSHAIR, %ecx
	call mp1_poke
	leave
	ret

# int mp1_ioctl_startgame (unsigned long ignore)
# initializes varibles and memory for the game to start
# Inputs   : unsigned long ignore - meaningless value that should be ignored
# Outputs  : ignored
# Registers: Standard C calling convention

mp1_ioctl_startgame:

	// initializing values that are needed
	movl $0,mp1_missile_list
	movl $0,mp1_score
	movl $12,crosshairs_y
	movl $40,crosshairs_x
	movl $0x00010101, base_alive
	ret

# int mp1_ioctl_addmissile (struct missile * user_missile)
# allocates memory for a missile to be added to the game
# and adds it to the linked list
# Inputs   : structure missile * user_missile - pointer to a struct missile in user space
# Outputs  : 0 if succeeds, -1 if fails
# Registers: Standard C calling convention

mp1_ioctl_addmissile:

	// allocates 3 bytes (size of struct missile)
	pushl $33
	call mp1_malloc
	pushl 8(%esp)
	pushl %eax
	call mp1_copy_from_user	# get missile detail

	// if malloc failed, will return 0, and throw an error
	cmpl $0,%eax
	jb addmissile_fail

	// puts the news missile at the head of the linked list
	movl mp1_missile_list, %eax
	pushl %ebx
	movl 4(%esp), %ebx
	movl %eax, (%ebx)
	movl %ebx, mp1_missile_list
	popl %ebx
	movl $0, %eax
	addl $12, %esp	
	ret

addmissile_fail:	

	// frees memory that failed to allocate, return -1 if failed
	call mp1_free
	movl $-1,%eax
	addl $12,%esp
	ret

# int mp1_ioctl_movexhairs (unsigned long xhair_delta_packed)
# moves the crosshair, while making sure it doesn't move off the screen
# while also erasing the old crosshair location and drawing at the new crosshair location
# Inputs   : unsigned long xhair_delta_packed - 32-bit integer contained the x location and y location 
#			 low 16 bits: x, high 16 bits: y			 
# Outputs  : always returns 0
# Registers: Standard C calling convention

mp1_ioctl_movexhairs:

	// clears old crosshair
	imull $160, crosshairs_y, %eax
	imull $2, crosshairs_x, %ecx
	addl %ecx, %eax
	movl $EMPTY, %ecx
	call mp1_poke

	// updates crosshair x location
	// moves x back to 79 if moved too far right
	// moves x back to 0 if moved too far left
	movl $0, %eax
	movw 4(%esp), %ax
	movswl %ax, %eax
	addl %eax, crosshairs_x
	cmpl $79, crosshairs_x
	jg fix_x_positive
	cmpl $0, crosshairs_x
	jl fix_x_negative
	jmp	update_crosshair_y

fix_x_positive:	
	
	// if moved too far right, move crosshair back to max x location, 79
	movl $79,crosshairs_x
	jmp	update_crosshair_y

fix_x_negative:	

	// if moved too far left, move crosshair back to min x location, 0
	movl $0, crosshairs_x

update_crosshair_y:

	// updates crosshair y location
	// moves y back to 24 if moved too far down
	// moves y back to 0 if moved too far up
	movl $0, %eax
	movw 6(%esp), %ax
	movswl %ax, %eax
	addl %eax, crosshairs_y
	cmpl $24, crosshairs_y
	jg fix_y_positive
	cmpl $0, crosshairs_y
	jl fix_y_negative
	jmp	exit_movexhairs

fix_y_positive:
	
	// if moved too far down, move crosshair back to max y location, 24
	movl $24, crosshairs_y
	jmp	exit_movexhairs

fix_y_negative:

	// if moved too far up, move crosshair back to min y location, 0
	movl $0,crosshairs_y

exit_movexhairs:	
	
	// return 0
	movl $0, %eax
	ret

# int mp1_ioctl_getstatus (unsigned long * user_status)
# retrieves the current score and status of the three cities
# and puts it into * user_status
# Inputs   : unsigned long * user_status - pointer to a 32-bit integer in user space
#			 low 16 bits: current score
#			 bit 16, 17, 18: status of the three cities
#			 	(1 if alive, 0 if dead)			 
# Outputs  : returns 0 if success, -1 if fail
# Registers: Standard C calling convention

mp1_ioctl_getstatus:

	// if user_status is null, error, exit
	pushl base_alive		
	cmpl $0, 8(%esp)
	je getstatus_fail_1

	// check bases 1, 2, 3
	// Updates bits 16, 17, 18 accordingly
	movl $0, %eax
	cmpb $0,3(%esp)
	je check_base_2
	addl $0x40000,%eax	

check_base_2:	
	
	// checks base 2
	cmpb $0,2(%esp)	
	je check_base_3
	addl $0x20000,%eax

check_base_3:	

	// checks base 3
	cmpb $0,1(%esp)
	je check_base_done
	addl $0x10000,%eax

check_base_done:

	// gives user_status to to user through mp1_copy_to_user
	addl mp1_score,%eax
	pushl %eax
	movl %esp,%eax
	pushl $4
	pushl %eax
	pushl 20(%esp)
	call mp1_copy_to_user
	cmpl $0,%eax	
	jne	getstatus_fail
	addl $20,%esp
	movl $0, %eax
	ret

getstatus_fail:	

	// returns -1, pops mp1_copy_to_user values off the stack
	movl	$-1,%eax
	addl	$16,%esp

getstatus_fail_1:	

	// pops the additional base_alive that was pushed onto the stack
	addl	$4,%esp
	ret

# int mp1_ioctl_endgame (unsigned long ignore)
# executes when the game finishes. clears our linked list
# Inputs   : unsigned long ignore - ignored			 
# Outputs  : always returns 0
# Registers: Standard C calling convention

mp1_ioctl_endgame:

	// saves ebx so we can use the register
	pushl %ebx
	movl mp1_missile_list, %ebx	

start_endgame:	

	// clears our linked list until we hit NULL, which is the end
	cmpl $0,%ebx
	je end_endgame
	pushl %ebx
	movl NEXT(%ebx),%ebx
	call mp1_free

	// push mp1_missile_list off the stack
	addl $4,%esp
	jmp start_endgame

end_endgame:	

	// pops our final ebx, return 0
	popl %ebx
	movl $0, %eax
	ret
