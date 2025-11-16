`timescale 1ns / 1ps
module assemble(iODCK, iDE, iHSYNC, iVSYNC, iQE, iSW0, iSW1, iSW2, VSYNC_GS, oWEA, oData, oAddress);

    //DVI Signal
    input iODCK;
    input iDE;
    input iHSYNC;
    input iVSYNC;
    input [23:0] iQE;
    
    //NKFUST Board
    input       iSW0;//input sw
    input [1:0] iSW1;//mode sw
    input [7:0] iSW2;//parameter sw

   //for 2 ram
	output VSYNC_GS;

   output oWEA;
   output [7:0] oData;
   output [8:0] oAddress;

//Format "Signal Name"+"_"+"Come From Block"
   wire VSYNC_GS, HSYNC_GS, DE_GS;
   wire [23:0] QE_GS;

   wire         VD_IU;
   wire [ 23:0] HD_IU;
   wire [191:0] PixelData_IU;
   wire [  3:0] VA_IU;
   wire         rstALG_IU, enOU_IU;
   wire [  6:0] VBC_IU;
   
	wire [191:0] BD_ALG24;

	GSNan GS (.iODCK(iODCK), .iDE(iDE), .iHSYNC(iHSYNC), .iVSYNC(iVSYNC), .iQE(iQE[23:0]), .iSW1pass0maker(iSW0),
//	GiveSingal GS (.iODCK(iODCK), .iDE(iDE), .iHSYNC(iHSYNC), .iVSYNC(iVSYNC), .iQE(iQE[23:0]), .iSW1pass0nothing(iSW0), 
                              .oDE(DE_GS), .oHSYNC(HSYNC_GS), .oVSYNC(VSYNC_GS), .oQE(QE_GS[23:0]));

   InUnit3 IU (.iODCK(iODCK), .iDE(DE_GS), .iHSYNC(HSYNC_GS), .iVSYNC(VSYNC_GS), .iQE(QE_GS[23:0]), .iDutySW016464(iSW1[1:0]),
                   .oH_Duty(HD_IU[23:0]), .oV_Duty(VD_IU), .oPixelData(PixelData_IU[191:0]), .oV_Address(VA_IU[3:0]), 
						 .oOU_en(enOU_IU), .oALG_rst(rstALG_IU), .oV_Block_Duty_Count(VBC_IU[6:0]) );

   algorithm24s ALG (.iODCK(iODCK),.iRST(rstALG_IU),  .iH_Duty(HD_IU[23:0]), .iV_Duty(VD_IU), .iV_Block_Duty_Count(VBC_IU[6:0]), 
	                  .iPixelData(PixelData_IU[191:0]), .iSW1(iSW1[1:0]), .iSW2(iSW2[7:0]), .oBlockData(BD_ALG24[191:0]));

   OutUnits OU (.iODCK(iODCK), .iDE(enOU_IU), .iBlockData(BD_ALG24[191:0]), .iV_address(VA_IU[3:0]), 
                    .oWEA(oWEA),.oData(oData[7:0]),  .oAddress(oAddress[8:0]));
   
endmodule
