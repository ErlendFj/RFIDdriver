{
RFIDspin - Spin only, educational-style code (for my own education) of a RFID reader.
Erlend Fjosna  
--------------------------------------------------------------------------------------
 This object reads the Parallax RFID card reader, converts the 12byte sequence code to a string of 10, head and tail removed,
 compares this string with a number of string-format codes in the DAT of the parent object, return-writes which number in the sequence had a match (0 if none).
 Retur-write the string-formatted code regardless of match or not.
 Optionally resets the number-match to zero after a time delay.
 Optionally displays the codes to the pst (if tpeDisplay=1). Should only be used for debugging or when obtaining card codes, because it claims the usb comms channel.

 I have taken some of the Read code ideas from RFID_Demo.spin by Gavin Garner, thanks.

 Naming convention: Variable naming: stn: String, int: Integer, flt: Floating point, cmp: Composite, chr: Character, dta: Consecutive bytes containing data sets
                    Constant naming: stn: String, Cint: Integer, Cflt: Floating point, Ccmp: Composite, Cchr: Character, Cdta: Consecutive bytes containing data sets
                    PIN constant numbers are 'intFncPIN' wher Fnc is an abbreviation of the signal/function
                    Reserved words are always in capitals
                    Called objects are three letter lower case
                    PUB and PRI have first letter capital then lower case. Local variables are free text in lower case.

=======================================================================================================================================================================
 Hardware & wiring:
 ----
     |
     |- VCC    --------- 5V (WILL NOT WORK WITH 3.3)
RFID |- ENABLE --------- intEnaPIN
     |- SOUT   --~10k--- intSerPIN
     |- GND    --------- Ground
     |
-----
Data sheet: http://www.parallax.com/StoreSearchResults/tabid/768/txtSearch/rfid/List/0/SortField/4/ProductID/114/Default.aspx


=======================================================================================================================================================================
}

CON
        _clkmode = xtal1 + pll16x                                  'Standard clock mode * crystal frequency = 80 MHz
        _xinfreq = 5_000_000                      

VAR
  BYTE intCog, datRFID[12], txtRFID[11]                             
  LONG stack[200]


  LONG NumberMatch
  BYTE isRFID[11]


   
OBJ
    pst   : "Parallax Serial Terminal"
    

PUB Main  | value

   pst.Start(9600)                                                      'Remember to start the terminal at 9600b/s
   WAITCNT(clkfreq + cnt)                                         

   pst.Str(String("Test of RFID reader, press to start"))
   value := pst.DecIn
   pst.Chars(pst#NL, 2)

   start(22, 23, @Codes, 7, 10, 1, @NumberMatch, @isRFID)

   REPEAT
     pst.Str(String("Swipe: "))
     pst.Dec(NumberMatch)
     pst.Str(String("  RFID:  "))
     pst.Str(@isRFID)   
     pst.Chars(pst#NL, 2)
     WAITCNT(2*clkfreq + cnt)

     
  
PUB start(intSerPIN, intEnaPIN, stnCodes{ptr}, intNumberofCodes, intSecTimeout, intTypeDisplay, intNumberMatch{ptr}, stnRFID{ptr})

    stop                                                  
    intCog:= COGNEW(rfid(intSerPIN, intEnaPIN, stnCodes{ptr}, intNumberofCodes, intSecTimeout, intTypeDisplay, intNumberMatch{ptr}, stnRFID{ptr}), @stack[0]) + 1

PUB stop

  IF (intCog)                                                      
    COGSTOP(intCog - 1)                                         
    intCog := 0      

    
PRI rfid(intSerPIN, intEnaPIN, stnCodes{ptr}, intNumberofCodes,{
       } intSecTimeout, intTypeDisplay, intNumberMatch{ptr}, {
       } stnRFID{ptr}) | deltaT, time, i, j, value, match, count
                                                                   'PRI instead of PUB to prevent parent code to call .RFID direct (silly)
    match := 0                                                        
    count := 10*CLKFREQ + CNT                                      'Allow Read 10 sec to read card to avoid Timeout to trigger first time
                                 
    
    repeat                                                         'Infinitely do
     'Read procedure
     '--------------
      DIRA[intSerPIN]~                                             'Set direction of intSerPIN to be an input            
      DIRA[intEnaPIN]~~                                            'Set direction of intEnaPIN to be an output                             
      deltaT:=CLKFREQ/2400                                         'Set deltaT to 1/2400th of a second for 2400bps "Baud" rate  
      OUTA[intEnaPIN]~                                             'Enable the RFID reader      
       repeat i from 0 to 11                                       'Fill in the 12 byte arrays with data sent from RFID reader
           
         repeat while i == 0 AND (INA[intSerPIN] == 1)             'Detour for Timeout procedure, while card has not yet started outputting  
           if CNT - count > intSecTimeout*CLKFREQ AND match > 0    'If time is exceeded and match not alredy reset 
              match := 0                                           'Reset local
              LONG [intNumberMatch] := 0                           'Reset global
              BYTEMOVE(stnRFID, String("No card   "), 11) 
                                                                   '-continue reading 
         if i > 0                                                  'Waitpeq for the first signal is taken care of by Timeout loop 
           WAITPEQ(1 << intSerPIN,|< intSerPIN,0)                  'Wait for a high-to-low signal on RFID's intSerPIN pin, which  
         WAITPEQ(0 << intSerPIN,|< intSerPIN,0)                    'signals the start of the transfer of each packet of 10 data bits plus head and tail   
         time:=CNT                                                 'Record the counter value at start of each transmission packet  
         WAITCNT(time+=deltaT+deltaT/2)                            'Skip the start bit (always zero) and center on the 2nd bit
              
         repeat 8                                                  'Gather 8 bits for each byte of RFID's data         
           datRFID[i]:=datRFID[i]<<1 + INA[intSerPIN]              'Shift datRFID bits left and add current bit (state of intSerPIN)  
           WAITCNT(time+=deltaT)                                   'Pause for 1/2400th of a second (2400 bits per second)           
         datRFID[i]><=8                                            'Reverse the order of the bits (RFID scanner sends LSB first)                             
      OUTA[intEnaPIN]~~                                            'Disable the RFID reader
      
      BYTEMOVE(@txtRFID, @datRFID+1, 10)                           'Copy second to tenth byte into new variable to get rid of the header and tail
      txtRFID[10] := 0                                             'Make it a zero-termINAted STRING 
      BYTEMOVE(stnRFID, @txtRFID, 11)                              'Copy same to parent object variable, i.e. report RFID read                                    

      
     'Find match procedure
     '-------------------
      match := 0                                         
      repeat j from 0 to intNumberofCodes - 1                     'For each of the codes in DAT block of STRINGs,                                        
        IF STRCOMP(@txtRFID, stnCodes+11*j)                       '-compare read RFID with the j'th code                                                                                         
           match := j+1                                           'Set the number of the one code which matches
           LONG [intNumberMatch] := match                         'Copy the match number to the parent object
           count := CNT                                           'After successful read and match, reset timeout

      WAITCNT(CLKFREQ + CNT)                                      'Wait one second to read the card again - to 'debounce'


DAT

Codes        BYTE  "0100A648BD", 0     {1 Erlend}
             BYTE  "0100E3E9CB", 0     {2 Lisa}
             BYTE  "8400338B3C", 0     {3 Mathias}
             BYTE  "8400336BB8", 0     {4 Irene}
             BYTE  "8400338FC0", 0     {5 William}
             BYTE  "8400338778", 0     {6 Guest1}
             BYTE  "8400338778", 0     {7 Guest2}

Hit          BYTE  "Matching!!", 0
         

{{

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                   TERMS OF USE: MIT License                                                  │                                                            
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation    │ 
│files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,    │
│modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software│
│is furnished to do so, subject to the following conditions:                                                                   │
│                                                                                                                              │
│The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.│
│                                                                                                                              │
│THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE          │
│WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR         │
│COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,   │
│ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                         │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
}}