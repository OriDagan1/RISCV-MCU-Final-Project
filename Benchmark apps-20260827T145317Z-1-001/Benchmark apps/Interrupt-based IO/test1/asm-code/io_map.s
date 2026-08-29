#--------------------------------------------------------------
#		    		MEMORY Mapped I/O addresses
#--------------------------------------------------------------
.eqv PORT_LEDR 	0x2000     		# define a byte address (GPO)

.eqv PORT_HEX0 	0x2004     		# define a byte address (GPO)
.eqv PORT_HEX1 	0x2005     		# define a byte address (GPO)

.eqv PORT_HEX2 	0x2008     		# define a byte address (GPO)
.eqv PORT_HEX3 	0x2009     		# define a byte address (GPO)

.eqv PORT_HEX4 	0x200C					# define a byte address (GPO)
.eqv PORT_HEX5 	0x200D     		# define a byte address (GPO)

.eqv PORT_SW 		0x2010					# define a byte address (GPI)
.eqv PORT_PB 		0x2014					# define a byte address (GPI)
#--------------------------------------------------------------
.eqv UTCL 			0x2018					# define a byte address
.eqv RXBUF 			0x2019					# define a byte address
.eqv TXBUF 			0x201A					# define a byte address
#--------------------------------------------------------------
.eqv BTCTL1 		0x201C					# define a byte address
.eqv BTCTL2 		0x201D					# define a byte address
.eqv BTCMPR0 		0x2020					# define a Word address
.eqv BTCMPR1 		0x2024					# define a Word address
.eqv BTCAPR 		0x2028					# define a Word address
#--------------------------------------------------------------
.eqv IE 				0x202C					# define a byte address
.eqv IFG 				0x202D					# define a byte address
.eqv TYPE 			0x202E					# define a byte address
#--------------------------------------------------------------
#		    		Mask Constants
#--------------------------------------------------------------
.eqv BTHOLD_BTSSEL3_BTCLR		0x3C 
.eqv BTSSEL3			 					0x18
.eqv BTIE			 							0x04
.eqv KEY3IE_KEY2IE_KEY1IE		0x38
.eqv KEY1IFG_MASK			 			0xFFF7
.eqv KEY2IFG_MASK			 			0xFFEF
.eqv KEY3IFG_MASK			 			0xFFDF

.eqv reti									jalr zero,0(tp)


