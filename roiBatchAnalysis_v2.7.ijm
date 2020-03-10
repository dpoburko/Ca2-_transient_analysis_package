/*
SENAN F. 
Created Mar-2014
Edited and modified - D Poburko 
v1.1 DP - added minimum pixel & rolling ball subtraction for image to be analyzed
v1.4.8.3 - replace dilation with distance map for dilated nucleus
v2.0 - re-arranging to allow selection of multiple ROI types per channel
	- so far have modified dialog
	- need to laop through all analysis options in one large array
	- add choice to make cell ROIs from nuclear voronoi (effectively v lg radius of nuclear surround)
	- add options to use local max as particle search .... on second thought, this should be roled into mulitple thresholds batch, where cell ROIs are generated here
	- sort out how to have multiple analyses show up on same line of the results table (probably requires searching results table for given image name) and add col for ch, roi Shape, and metrics
	- restore option to find nuc ROIs from z-stack
	- modified method of creating nuc surrounds. Much faster now.
v2.5p - need to figur out how to convert text window to results table
v2.6 - 
v2.7 - add ability to call seededClustR from this macro to generate concave hull around nuclei 
*/

/*------------------------------
Support functions
------------------------------*/
var version = "v2.7";
var RIPAversion = "v1.1";
var gImageNumber = -1;
var gImageFolder  = call("ij.Prefs.get", "dialogDefaults.imageDirectory", "");
var gCurrentImageName = "";
var gOutputImageFolder = "";
var gNuclearImageFolder = "";
var gFftImageFolder = "";
var gImageList;
var gResultFileName = "ROI Intensities.xls";
var gKi67Channel = 2;
var gNuclearChannel = 1;
var gNuclearMinArea = 14000;
var gBallSize = -1;
var gBallSizeMeasured = -1;
var gNucSurroundOrBox = -1;
var gNucSurround = "";
var gKi67ChannelGauss = -1;
var gAnalyzeFFTsets = false;
var items = newArray("nucleus","box_around_nucleus","dilated_nucleus","nuclear_surround","seededClustR");
var roiLabels = newArray("nucleus","nucBox","nucDilated","nucSurround","concavehull");
var overwriteROIs = false;
var nucThreshold = -1;
var circThreshold = -1;
var gaussRad = -1;
var minSolid = -1;
var gExpCellNumberStart = 0;
var gUniqueCellIndex = 0;
var gPreviousImgName = "";
var gDoMultipleThresholds = false;
var gDoWaterShed = false;
var gNumAnalyses = 1;
var gDefineNucROIs ="No";
var firstChannel = 1;
var firstRoiShape = items[0];
var endCellsAnalysis1 = 0;
var startCellsAnalysis1 = 0;
var nImgsToProcess = 0;
var usRadius = 1;
var usMask = 1;
var clearFlags = false;
var nucOffSet = 6;
var slices2channels = false;

var gRIPAParameters = "[nsds]=2 [stepmthd]=[step size] [nthrorsize]=50 [umt]=-1 [lmt]=100 [trmtd]=none [minps]=400 [maxps]=6000 [mincirc]=0.100 [maxcirc]=1 [minSolidity]=0.100 [maxSolidity]=1 [bgsub]=-1 exclude=20 [nomrg] [svrois] [called]";
// run("RIPA v4.9.1", "[nsds]=2 [stepmthd]=[step size] [nthrorsize]=200 [umt]=4000 [lmt]=200 [trmtd]=none [minps]=400 [maxps]=8000 [mincirc]=0.300 [maxcirc]=1 [minround]=0 [maxround]=1 [bgsub]=-1 [wtshd] exclude=20 [nomrg]");



c1ShapesSelection = items;
analysesToDo = newArray(4*items.length);
itemsDefaults = newArray(items.length);
Array.fill(itemsDefaults,-1);

macro "Image Intensity Process" {
	
	requires("1.48h");

	doSetImageFolder();

	// check for a prefs file
	run("Clear Results");
	paraFlist = getParameterFiles(); //checks for a file in the image folder containing preferred image analysis parameters
	Array.print(paraFlist);
	if (paraFlist[0]!="") {
		if (paraFlist.length==1) {
			pFile = paraFlist[0];
		}
		if (paraFlist.length>=2) {
			Dialog.create("select parameters file");
			Dialog.addChoice("select parameters file",paraFlist,paraFlist[0]);
			Dialog.show();
			pFile = Dialog.getChoice();
		}
		run("Clear Results");
	    open(gImageFolder+pFile);
	    Table.rename(pFile,"Results");
		getParameters();
	}
	
	nucROIsExist = "No";
	doNucROIsPrevious = call("ij.Prefs.get", "dialogDefaults.gDefineNucROIs","No");
	doNucROIs = newArray(doNucROIsPrevious,"No","multiple thresholds","simple threshold");
	for ( i =0; i< gImageList.length; i++) {
		if (( endsWith(gImageList[i], ".zip") == true) || ( indexOf(gImageList[i], "nuc") == true) ) {
			nucROIsExist = "Likely";
			i = gImageList.length;
		}
	}
	
 	// === DIALOG 0 ===================================================================================================================================================
 	// ================================================================================================================================================================
	help1 = "<html>"
     +"<h2>HTML formatted help</h2>"
     +"<font size=+1>
     +"In ImageJ 1.46b or later, dialog boxes<br>"
     +"can have a <b>Help</b> button that displays<br>"
     +"<font color=red>HTML</font> formatted text.<br>"
     +"</font>";

	message = "This macro will help to generate ROIs around puncta of interest in up to 6-channel images \n"
	+ "with up to 12 analysis/channel pairings. It is strongly recommended to start with nuclear ROIs. \n"
	+ "• ROI around reference puncta can be simepl ROIs, boxes, dilated ROIs or 'surrounds' of your ROIs. \n"
	+ "• Large folders of images can be analyzed by multiple instances of ImageJ or computers in parallel. \n"
	+ "• Paste the '0_parameters' file to a new folder to re-use previous options";
	
	Dialog.create("Set Channels & Regions to Analyze " + version);
	Dialog.addMessage(message );
	Dialog.addSlider("Nuclear or main ROI Channel", 1, 6, parseInt(call("ij.Prefs.get", "dialogDefaults.gNuclearChannel",gNuclearChannel)));
	Dialog.addNumber("number of channel / ROI shape pairings to analyze ",  parseInt(call("ij.Prefs.get", "dialogDefaults.gNumAnalyses",gNumAnalyses)));
	//Dialog.setInsets(0, 20, 0);
	Dialog.addChoice(nucROIsExist + " nuclear ROIs found. (Re)define nuclear ROIs?",doNucROIs,doNucROIs[0]);
	Dialog.addCheckbox("run in Batch Mode (doesn't work with multipleThresholds / RIPA) ",call("ij.Prefs.get", "dialogDefaults.gDoBatchMode",true));
	Dialog.addCheckbox("Notify by email when done (requires PC system modifications)", false);
	Dialog.addCheckbox("clear previous analysis 'done' flags", false);
	//Dialog.addCheckbox("convert Matlab AIF slices to channels", call("ij.Prefs.get", "dialogDefaults.slices2channels",false));
	Dialog.show();
	gNuclearChannel = Dialog.getNumber();     	call("ij.Prefs.set", "dialogDefaults.gNuclearChannel",gNuclearChannel);
	gNumAnalyses = Dialog.getNumber();			call("ij.Prefs.set", "dialogDefaults.gNumAnalyses",gNumAnalyses); 	
	gDefineNucROIs = Dialog.getChoice();		call("ij.Prefs.set", "dialogDefaults.gDefineNucROIs",gDefineNucROIs); 	  	
	gDoBatchMode = Dialog.getCheckbox();		call("ij.Prefs.set", "dialogDefaults.gDoBatchMode",gDoBatchMode); 	  	
	doSendEmail = Dialog.getCheckbox();  		call("ij.Prefs.set", "dialogDefaults.doSendEmail",doSendEmail); 	
	clearFlags = Dialog.getCheckbox();  		call("ij.Prefs.set", "dialogDefaults.clearFlags",clearFlags); 	
	//slices2channels = Dialog.getCheckbox();  	call("ij.Prefs.set", "dialogDefaults.slices2channels",slices2channels); 	  	
    slices2channels = false;

	//Save parameters to result table for saving in separate file
	setResult("Parameter",nResults,"gNuclearChannel");
	setResult("Values00",nResults-1,gNuclearChannel);
	setResult("Parameter",nResults,"gNumAnalyses");
	setResult("Values00",nResults-1,gNumAnalyses);
	setResult("Parameter",nResults,"gDefineNucROIs");
	setResult("Values00",nResults-1,gDefineNucROIs);
	setResult("Parameter",nResults,"gDoBatchMode");
	setResult("Values00",nResults-1,gDoBatchMode);
	setResult("Parameter",nResults,"doSendEmail");
	setResult("Values00",nResults-1,doSendEmail);
	setResult("Parameter",nResults,"clearFlags");
	setResult("Values00",nResults-1,clearFlags);
	setResult("Parameter",nResults,"slices2channels");
	setResult("Values00",nResults-1,slices2channels);

		
 	// === DIALOG 1 = define nuclear ROIs ==================================================================================================================================================
 	// ================================================================================================================================================================
	help2 = "<html>"
     
     +"<font size=+1>
     +"<b>Typical nuclear areas in pixels for Nikon TiE and Andor Zyla5.5:</b><br>"
     +"<font size=-1>
     +" <br>"
     +"<b>A7r5:</b> 2N cells 150-300 µm<sup>2</sup>. 8N cells 600-1200 µm<sup>2</sup> <br>"
     +"minimum nucleae area in pixel<sup>2</sup>: >300 @ 10X, >1400 20X, >3000 @ 30X, >35,000 @ 100x <br>" 
	 +" <br>"
     +"<b>N2a cells:</b> min ~### µm<sup>2</sup> <br>"
     +"minimum nucleae area in pixel<sup>2</sup>: 10X ?, 20X ?, 30X ?, 100x ?  <br>"
     +" <br>"
     +"<font color=blue> Consider smaller sizes if you suspect cells are apoptotic.</font> <br>" ;

	if (gDefineNucROIs == doNucROIs[3]) {
		Dialog.create("Define nuclear ROIs by a simple threshold");
		Dialog.setInsets(0, 20, 0);
		Dialog.addNumber("_Nuclear Min Area (pixels^2). Examples in help", parseInt( call("ij.Prefs.get", "dialogDefaults.gNuclearMinArea",gNuclearMinArea)));
		Dialog.addToSameRow();
		Dialog.setInsets(0, 20, 0);
		Dialog.addNumber("Threshold for nuclear binarization (-1 = off)",  parseInt(call("ij.Prefs.get", "dialogDefaults.nucThreshold",nucThreshold)));
		Dialog.setInsets(0, 20, 0);
		Dialog.addNumber("Rolling Ball Subtraction diameter for nuclei (-1 = off)",  parseFloat(call("ij.Prefs.get", "dialogDefaults.gBallSize",gBallSize)));
		Dialog.addToSameRow();
		Dialog.addNumber("Guassian blur radius  (-1 = off)",  parseFloat(call("ij.Prefs.get", "dialogDefaults.guassRad",gaussRad)));
		Dialog.setInsets(0, 20, 0);
		Dialog.addNumber("Unsharp Mask: Radius in pixels (-1 = off)",  parseInt(call("ij.Prefs.get", "dialogDefaults.usRadius",usRadius)));
		Dialog.addToSameRow();
		Dialog.addNumber("Strength (0.1-0.9)",  parseFloat(call("ij.Prefs.get", "dialogDefaults.usMask",usMask)));
		Dialog.setInsets(0, 20, 0);
		Dialog.addCheckbox("Watershed close nuclei ",call("ij.Prefs.get", "dialogDefaults.gDoWaterShed",false));
		Dialog.setInsets(0, 20, 0);
	
		Dialog.addNumber("... if circularity < (0.0-1.0) (0 = off)",  parseFloat(call("ij.Prefs.get", "dialogDefaults.circThreshold",circThreshold)));
	
		Dialog.setInsets(0, 20, 0);
		Dialog.addToSameRow();
		Dialog.addNumber("... if solidity < (0.0-1.0) (0 = off)",  parseFloat(call("ij.Prefs.get", "dialogDefaults.minSolid",minSolid)));
		Dialog.addCheckbox("overwrite ROI files ",call("ij.Prefs.get", "dialogDefaults.overwriteROIs",false));
		Dialog.addHelp(help2);
		Dialog.show();
		
		gNuclearMinArea = Dialog.getNumber();    	call("ij.Prefs.set", "dialogDefaults.gNuclearMinArea",gNuclearMinArea);
		nucThreshold =  Dialog.getNumber();	      	call("ij.Prefs.set", "dialogDefaults.nucThreshold",nucThreshold);
		gBallSize =  Dialog.getNumber();	      	call("ij.Prefs.set", "dialogDefaults.gBallSize",gBallSize);
		gaussRad =  Dialog.getNumber();		      	call("ij.Prefs.set", "dialogDefaults.gaussRad",gaussRad);
		usRadius =  Dialog.getNumber();	    	  	call("ij.Prefs.set", "dialogDefaults.usRadius",usRadius);
		usMask =  Dialog.getNumber();	      		call("ij.Prefs.set", "dialogDefaults.usMask",usMask);
		gDoWaterShed = Dialog.getCheckbox();	    call("ij.Prefs.set", "dialogDefaults.gDoWaterShed",gDoWaterShed);
		circThreshold =  Dialog.getNumber();	    call("ij.Prefs.set", "dialogDefaults.circThreshold",circThreshold);
		minSolid =  Dialog.getNumber();	  			call("ij.Prefs.set", "dialogDefaults.minSolid",minSolid);
		overwriteROIs = Dialog.getCheckbox();	    call("ij.Prefs.set", "dialogDefaults.gDoWaterShed",overwriteROIs);

		//Save parameters to result table for saving in separate file
		setResult("Parameter", nResults,"define_Nuc_ROIs");
		setResult("Values00", nResults,"simpleThreshold");
		setResult("Parameter",nResults,"gNuclearMinArea");
		setResult("Values00",nResults-1,gNuclearMinArea);
		setResult("Parameter",nResults,"nucThreshold");
		setResult("Values00",nResults-1,nucThreshold);
		setResult("Parameter",nResults,"gBallSize");
		setResult("Values00",nResults-1,gBallSize);
		setResult("Parameter",nResults,"gaussRad");
		setResult("Values00",nResults-1,gaussRad);
		setResult("Parameter",nResults,"usRadius");
		setResult("Values00",nResults-1,usRadius);
		setResult("Parameter",nResults,"usMask");
		setResult("Values00",nResults-1,usMask);
		setResult("Parameter",nResults,"gDoWaterShed");
		setResult("Values00",nResults-1,gDoWaterShed);
		setResult("Parameter",nResults,"circThreshold");
		setResult("Values00",nResults-1,circThreshold);
		setResult("Parameter",nResults,"minSolid");
		setResult("Values00",nResults-1,minSolid);

		setResult("Parameter",nResults,"overwriteROIs");
		setResult("Values00",nResults-1,overwriteROIs);	
	} 

	

 	// === DIALOG 3 ===================================================================================================================================================
 	// ================================================================================================================================================================


	if (gDefineNucROIs == doNucROIs[2]) {
		gDoMultipleThresholds = true;
		gRIPAParameters1 = call("ij.Prefs.get", "dialogDefaults.gRIPAParameters1","[nsds]=2 [stepmthd]=[step size] [nthrorsize]=100 [umt]=-1 [lmt]=50 [trmtd]=none");
		gRIPAParameters2 = call("ij.Prefs.get", "dialogDefaults.gRIPAParameters2", "[minps]=400 [maxps]=6000 [mincirc]=0.100 [maxcirc]=1 [minsolidity]=0.100 [maxolidity]=1");
		gRIPAParameters3 = call("ij.Prefs.get", "dialogDefaults.gRIPAParameters3", "[bgsub]=-1 exclude=20 [nomrg] [svrois] [called]");
		Dialog.create("Confirm MultipleThresholds Parameters");
	    Dialog.addMessage("WARNING! Do not select options [svrois] or [called] below. \n This will cause a crash");
	    Dialog.addString("version of multipleThresholds used: ",call("ij.Prefs.get", "dialogDefaults.RIPAversion",RIPAversion));
	    Dialog.addMessage("Define thresholds: [nsds]=2 [stepmthd]=[step size] [nthrorsize]=100 [umt]=-1 [lmt]=50 [trmtd]=none");
		Dialog.addString("mandatory fields: ", gRIPAParameters1,90);
		Dialog.addMessage("Puncta shapes collected: [minps]=400 [maxps]=6000 [mincirc]=0.100 [maxcirc]=1 [minsolidity]=0.100 [maxsolidity]=1");
		Dialog.addString("mandatory fields",gRIPAParameters2,90);
		Dialog.addMessage("Extra Options: [bgsub]=-1 [wtshd] exclude=20 [cntrs] [nomrg] show [svmsk] thresholds [svrois] [called]");
		Dialog.addString("Simply omit if no value in template: ", gRIPAParameters3,90);
		Dialog.addCheckbox("overwrite ROI files ",call("ij.Prefs.get", "dialogDefaults.overwriteROIs",false));
		
		Dialog.show();
		RIPAversion = Dialog.getString();      call("ij.Prefs.set", "dialogDefaults.RIPAversion",RIPAversion);
		gRIPAParameters1 = Dialog.getString(); call("ij.Prefs.set", "dialogDefaults.gRIPAParameters1",gRIPAParameters1);
		gRIPAParameters2 = Dialog.getString(); call("ij.Prefs.set", "dialogDefaults.gRIPAParameters2",gRIPAParameters2);
		gRIPAParameters3 = Dialog.getString(); call("ij.Prefs.set", "dialogDefaults.gRIPAParameters3",gRIPAParameters3);
		gRIPAParameters = gRIPAParameters1 + " " + gRIPAParameters2 + " " + gRIPAParameters3;
		gRIPAParameters = replace(gRIPAParameters, "  ", " ");
		overwriteROIs = Dialog.getCheckbox();	    call("ij.Prefs.set", "dialogDefaults.gDoWaterShed",overwriteROIs);

		dirIJ = getDirectory("imagej");
		path =  dirIJ+  "plugins" + File.separator + "Macros" + File.separator + "DTP_multiple_thresholdsMacro_"+RIPAversion+".ijm";
		//print(path);
		if (File.exists(path)== false) exit("please install DTP_multiple_thresholdsMacro_"+RIPAversion+" \n to your Macros folder.");

		//Save parameters to result table for saving in separate file
		setResult("Parameter", nResults,"define_Nuc_ROIs");
		setResult("Values00", nResults-1,"RIPA");
		setResult("Parameter",nResults,"gRIPAParameters1");
		setResult("Values00",nResults-1,gRIPAParameters1);
		setResult("Parameter",nResults,"gRIPAParameters2");
		setResult("Values00",nResults-1,gRIPAParameters2);
		setResult("Parameter",nResults,"gRIPAParameters3");
		setResult("Values00",nResults-1,gRIPAParameters3);

	}

	call("ij.Prefs.set", "dialogDefaults.gRIPAParameters",gRIPAParameters); 

	//getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	//stamp = ""+ year +""+IJ.pad(month+1,2)+""+ dayOfMonth+"-"+IJ.pad(hour,2)+""+IJ.pad(minute,2)+""+IJ.pad(second,2) ;
	stamp = timeStamp();
 	
 	// === DIALOG 2 ===================================================================================================================================================
 	// ================================================================================================================================================================

	minus1 = "-1";
	var roiShapes = newArray(gNumAnalyses);
	var channels = newArray(gNumAnalyses);
	var ballSizes = newArray(gNumAnalyses);
	var gaussRadii = newArray(gNumAnalyses);
	var roiSizes = newArray(gNumAnalyses);
	var threshold32s = newArray(gNumAnalyses);

	  html1 = "<html>"
     +"<h2>Use of rolling ball size:</h2>"
     +".   nucleus - not used <br>"
     +".   box = edge length <br>"
     +".  dilated_nucleus  - pixels of dilation around nucleus with Voronoi limits <br>"
     +".  nuclear_surround - pixels of dilation around nucleus with Voronoi limits <br>"
     +"<br>"
     +"<h2>Typical nuclear sizes</h2>"
     +".    (A7r5, diploid) = ~300 µm diameter<br>"
     +".     ~200px @ 20X, ~300px @ 30X, ~400px @ 40X, ~600px @ 100X "
	 +"</font>";

	dialogName = "Select Channel & ROI shape pairs";
	if (gNumAnalyses>5) { 
		dialogName= "Select Channel & ROI shape pairs for first 5 options";
	}
	
	    Dialog.create(dialogName);
		for (i=0; i<minOf(gNumAnalyses,4); i++) {
			Dialog.setLocation(20,20); 
			Dialog.addChoice("channel/shape pair "+(i+1)+" ROI shape", items, call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"shape",items[0]));	
			Dialog.addSlider("Channel", 1, 6, parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"channel",minus1)));
			Dialog.addNumber("Rolling ball subtraction (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"ballSize",minus1)));
			Dialog.addNumber("Smooth with Gaussian filter of radius (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"gaussRad",minus1)));
			Dialog.addNumber("Size (not used for 'nucleus' ROIs): ",parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"roiSize",minus1)));
			Dialog.addNumber("32bit threshold (-1=off):" ,parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"threshold32",minus1)));
		}
		
		//Dialog.addMessage("Size for: nucleus - not used, box - edge length \n dilated_nucleus and nuclear_surround - pixels of dilation around nucleus with Voronoi limits");
		Dialog.addMessage("See help for guidelines");
		Dialog.addHelp(html1);
		Dialog.show;
	
	    for (i=0; i<minOf(gNumAnalyses,4); i++) {
			roiShapes[i] = Dialog.getChoice();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"shape",roiShapes[i]);
			channels[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"channel",channels[i]);
			ballSizes[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"ballSize",ballSizes[i]);
			gaussRadii[i] = Dialog.getNumber(); call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"gaussRadii",gaussRadii[i]);
			roiSizes[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"roiSize",roiSizes[i]);
			threshold32s[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"threshold32",threshold32s[i]);
	    }
	
	    if (gNumAnalyses>4) {
			dialogName= "Select Channel & ROI shape pairs for options 5 to " + minOf(gNumAnalyses,8);
		    Dialog.create(dialogName);
			for (i=4; i<minOf(gNumAnalyses,8); i++) {
				Dialog.setLocation(20,20); 
				Dialog.addChoice("channel/shape pair "+(i+1)+" ROI shape", items, call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"shape",items[0]));	
				Dialog.addSlider("Channel", 1, 6, parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"channel",minus1)));
				Dialog.addNumber("Rolling ball subtraction (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"ballSize",minus1)));
				Dialog.addNumber("Smooth with Gaussian filter of radius (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"gaussRad",minus1)));
				Dialog.addNumber("Size: ",parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"roiSize",minus1)));
				Dialog.addNumber("32bit threshold:" ,parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"threshold32",minus1)));
			}
			//Dialog.addMessage("Size for: nucleus - not used, box - edge length \n dilated_nucleus and nuclear_surround - pixels of dilation around nucleus with Voronoi limits");
			Dialog.addMessage("See help for guidelines");
			Dialog.addHelp(html1);
			Dialog.show;
		    for (i=4; i<minOf(gNumAnalyses,8); i++) {
				roiShapes[i] = Dialog.getChoice();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"shape",roiShapes[i]);
				channels[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"channel",channels[i]);
				ballSizes[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"ballSize",ballSizes[i]);
				gaussRadii[i] = Dialog.getNumber(); call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"gaussRadii",gaussRadii[i]);
				roiSizes[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"roiSize",roiSizes[i]);
				threshold32s[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"threshold32",threshold32s[i]);
		    }
	    }
			//print("gNumAnalyses: "+gNumAnalyses);
        if (gNumAnalyses>8) {
			dialogName= "Select Channel & ROI shape pairs for options 9 to " + gNumAnalyses;
		    Dialog.create(dialogName);
			for (i=8; i<gNumAnalyses; i++) {
				Dialog.setLocation(20,20); 
				Dialog.addChoice("channel/shape pair "+(i+1)+" ROI shape", items, call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"shape",items[0]));	
				Dialog.addSlider("Channel", 1, 6, parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"channel",minus1)));
				Dialog.addNumber("Rolling ball subtraction (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"ballSize",minus1)));
				Dialog.addNumber("Smooth with Gaussian filter of radius (-1=off):",parseFloat(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"gaussRad",minus1)));
				Dialog.addNumber("Size: ",parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"roiSize",minus1)));
				Dialog.addNumber("32bit threshold:" ,parseInt(call("ij.Prefs.get", "dialogDefaults.c"+(i+1)+"threshold32",minus1)));
			}
			//Dialog.addMessage("Size for: nucleus - not used, box - edge length \n dilated_nucleus and nuclear_surround - pixels of dilation around nucleus with Voronoi limits");
			Dialog.addMessage("See help for guidelines");
			Dialog.addHelp(html1);
			Dialog.show;
		    for (i=8; i<gNumAnalyses; i++) {
				roiShapes[i] = Dialog.getChoice();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"shape",roiShapes[i]);
				channels[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"channel",channels[i]);
				ballSizes[i] = Dialog.getNumber();	call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"ballSize",ballSizes[i]);
				gaussRadii[i] = Dialog.getNumber(); call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"gaussRad",gaussRadii[i]);
				roiSizes[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"roiSize",roiSizes[i]);
				threshold32s[i] = Dialog.getNumber();   call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"threshold32",threshold32s[i]);
		    }
    	}
			//Save parameters to result table for saving in separate File.append(string, path)
			roiShapesTxt = ""; channelsTxt = ""; ballSizesTxt = ""; gaussRadiiTxt=""; roiSizesTxt = ""; threshold32sTxt="";
			
			for (i=0; i<gNumAnalyses; i++) {
				roiShapesTxt = roiShapesTxt  + roiShapes[i]+ ", ";
				channelsTxt = channelsTxt  + channels[i]+ ", ";
				ballSizesTxt = ballSizesTxt  + ballSizes[i]+ ", ";
				gaussRadiiTxt = gaussRadiiTxt  + gaussRadii[i]+ ", ";
				roiSizesTxt = roiSizesTxt  + roiSizes[i]+ ", ";
				threshold32sTxt = threshold32sTxt  + threshold32s[i]+ ", ";
			}
			setResult("Parameter", nResults,"roiShapes");
			setResult("Parameter", nResults,"channels");
			setResult("Parameter", nResults,"ballSizes");
			setResult("Parameter", nResults,"gaussRadii");
			setResult("Parameter", nResults,"roiSizes");
			setResult("Parameter", nResults,"threshold32s");
			setResult("Values00", nResults-6,roiShapesTxt);
			setResult("Values00", nResults-5,channelsTxt);
			setResult("Values00", nResults-4,ballSizesTxt);
			setResult("Values00", nResults-3,gaussRadiiTxt);
			setResult("Values00", nResults-2,roiSizesTxt);
			setResult("Values00", nResults-1,threshold32sTxt);
			
		startTime = timeStamp();
		saveAs("Results", gImageFolder  + "0parameters_nAnalyses_" + gNumAnalyses +"_rois_" +gDefineNucROIs + "_" + version + "_" + startTime + ".csv");//save to folder with timestamp
		updateResults();


	//print("channnes:");
	//Array.print(channels);
	//====== DIALOG 4.: email setings =================================================================================================================================
	//====== DIALOG 4.: email setings =================================================================================================================================
	
		if (doSendEmail == true) {
		  html = "<html>"
	     +"<h2>Windows requirement for sending email via ImageJ</h2>"
    	 +"<font size=+1>
     	+"run powershell.exe as an administator"
	     +"To do this: Type powershell.exe in windows search bar"
    	 +"... right click and select Run as Administrator"
	     +"type: 'Set-ExecutionPolicy RemoteSigned' "
    	 +"</font>";
  
		// Send Emamil Module 1: Place near beginning of code. Might want as an extra option after first dialog
		Dialog.create("Email password");
		Dialog.addMessage("Security Notice: User name and password will not be stored for this operation");
		Dialog.addString("Gmail address to send email - joblo@gmail.com", "polabsfu@gmail.com",60);
		Dialog.addString("Password for sign-in", "password",60);
		Dialog.addString("Email notification to:", "dpoburko@sfu.ca",60);
		Dialog.addString("Subject:", "Extended Depth of Field Conversion Complete",70);
		Dialog.addString("Body:", "Your Extended Depth of Field job is done.",70);
		Dialog.addHelp(html);
		Dialog.show();
		usr = Dialog.getString();
		pw = Dialog.getString();
		sendTo = Dialog.getString();
		subjectText = Dialog.getString();
		bodyText = Dialog.getString();
	}


	
	//prep logs and results table & IJ settings
	roiManager("reset");
	IJ.deleteRows(0, nResults);
	gImageNumber = 0;
	run("Set Measurements...", "area mean standard min centroid center perimeter fit shape integrated display redirect=None decimal=3");
 	oBackGroundColor = getValue("color.background");
	oForeGroundColor = getValue("color.foreground");
	run("Colors...", "foreground=white background=black selection=cyan");
	run("Input/Output...", "jpeg=85 gif=-1 file=.csv use_file copy_column copy_row save_column save_row");

	if (gDoBatchMode == true) setBatchMode(true);

	// make list of images
    validImgList = newArray(gImageList.length);
	nImgs = 0;

	// rename files containing the ### flag
	if (clearFlags == true) {
		for ( i =0; i< gImageList.length; i++) {
			if (indexOf(gImageList[i],"###")!=-1) {
				correctName = replace(gImageList[i],"###","");
				fr = File.rename(gImageFolder + gImageList[i],gImageFolder + correctName);
				gImageList[i] = correctName;
			}
		}
	}

	
	for ( i =0; i< gImageList.length; i++) {
		if ( (indexOf(gImageList[i],"###")==-1) && ( ( endsWith(gImageList[i], ".tif") == true) || ( endsWith(gImageList[i], ".nd2") == true) ) ) {
					validImgList[nImgs] = gImageList[i];
					nImgs++;
		}
	}
	validImgList = Array.slice(validImgList,0,nImgs);
	nValidImages =validImgList.length;
	Array.sort(validImgList);
	
	t0 = getTime();
	// cycle through image list and all analyses
	nImgsDone = 0;

	//set up foler to store txt files marking which images have been analyzed
	donePath = gImageFolder +  File.separator + "doneFlags" + File.separator;
	print("\\Update3: doneFlags folder: " + donePath);
		
		nDel = 0;
				if ((clearFlags == true)||(File.exists(donePath+ "allDone.txt"))) {
					if (File.isDirectory(donePath)) {
						doneList = getFileList(donePath);
						
						for(j=0;j<doneList.length;j++) {
							del = File.delete(donePath+doneList[j]);
							nDel++;
							print("\\Update3: "+nDel+" doneFlags deleted");
						}
					}
				}			

	if (!File.isDirectory(donePath)) File.makeDirectory(donePath);		
	
    for (nImgsToProcess=0; nImgsToProcess<nValidImages; nImgsToProcess++) {

		t1= getTime();
		currImageName = validImgList[nImgsToProcess];
		print("\\Update4: working on " + currImageName );
		skipImage = false;
		oSuffix = substring(currImageName, lastIndexOf(currImageName, "."),lengthOf(currImageName));
		tempSuffix = "###"+oSuffix;
		tempName = replace(replace(currImageName,"###",""), oSuffix, tempSuffix);
        doneTxtName = replace(currImageName, oSuffix, "###.txt");
		
		if ( ( File.exists(gImageFolder + tempName) ) || ( File.exists(donePath + doneTxtName ))  ) {
			print("\\Update2: Image exists in output directory");
			skipImage = true;
		}
				
		if (skipImage == false) {

    	    fr = File.rename(gImageFolder + currImageName,gImageFolder + tempName);
			fs = File.saveString("done",donePath  + doneTxtName);
			wait(500); 	//just in case another computer has already started working with this file
			if ( File.exists(gImageFolder + tempName) ) { 
		   		open(gImageFolder + tempName);
		   		rename(currImageName);
		   		getDimensions(width, height, ch, slc, frm);
				if ((ch == 1)&&(slc==1)) {
					run("Merge Channels...", "c1="+ currImageName + " c2="+ currImageName + " create");
					rename(currImageName);
				}
				//added in v2.5f to accomodate AIF processes extended depth of field from Matlab that are saved with channels as slices
				if ((ch == 1)&&(slices2channels==true)) {
					run("Stack to Images");
					mergeText = "";
					namesFromStack = newArray(nImages);
					for (m=1;m<=nImages();m++) {
						selectImage(m);
						namesFromStack[m-1] = getTitle;
						//print(getTitle());
					}
					for (m = 1; m<=slc;m++){
						mergeText = mergeText + "c"+m+"="+namesFromStack[m-1]+" ";
					}
					mergeText = mergeText + "create";
					run("Merge Channels...", mergeText);
					rename(currImageName);
					//waitForUser;
				}
				
		   		run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
		    	currLabelStart = nResults;
		   		roiManager("reset");
			    if (!isCompositeImage()) {
			        run("Channels Tool...");
			        run("Make Composite", "display=Composite");
			        selectWindow(currImageName);
			    }
		
		    	analyzedChannels = "";
		    	
				for (currAnalysis = 0; currAnalysis<gNumAnalyses; currAnalysis++) {
					currChannel = channels[currAnalysis];
					print("\\Update1: working on img " +nImgsToProcess+1+" of " + nValidImages + ", analysis " + currAnalysis+1 + " of " +gNumAnalyses +  ", Ch " + currChannel +" shape: " + roiShapes[currAnalysis]);
					roiLabelIndex = 0;
					for (i=0;i<items.length;i++) {
						if (roiShapes[currAnalysis] == items[i]) roiLabelIndex = i;
					}
					roiLabel = roiLabels[roiLabelIndex];
					
					//===== Send call to main processing function ====================================================================================================================================================
					//================================================================================================================================================================================================
					processSingleImage(currAnalysis, currImageName,currChannel,roiShapes[currAnalysis],roiSizes[currAnalysis], roiLabel, gaussRadii[currAnalysis], ballSizes[currAnalysis],threshold32s[currAnalysis]);
					analyzedChannels = analyzedChannels+"C"+currChannel+"_"+roiShapes[currAnalysis]+"_";
					//================================================================================================================================================================================================
					//================================================================================================================================================================================================
				}
				
				close("*");
				if (isOpen(currImageName)) {
					close(currImageName);
				}
				variantOfCurrImage = replace(currImageName,".","-1.");
				if (isOpen(variantOfCurrImage)) {
					close(variantOfCurrImage);
				}		
				
				fr = File.rename(gImageFolder + tempName,gImageFolder + currImageName);  // from failed attempt at parallel processing
		
				//Create progress bar in log
				lapTime = (getTime() - t1)/1000;
				t1 = getTime();
				nImgsDone++;
				LapsLeft = (nValidImages-1) - nImgsToProcess;
				tLeft = (  (t1-t0) / (nImgsDone) ) *  (LapsLeft)  / 1000 ;
				progress = ( nImgsToProcess + 1)/nValidImages ;
				pctDoneLength = 40;
				pctDone = progress*pctDoneLength;
				pctDoneString = "";
				pctLeftString = "";
				for(bb = 0; bb<pctDoneLength;bb++) {
					pctDoneString = pctDoneString + "|";
					pctLeftString = pctLeftString + ".";
				}
				pctDoneString = substring(pctDoneString ,0,pctDone);
				pctLeftString = substring(pctLeftString ,0,pctDoneLength - pctDone);
				
				if (tLeft>3600) {
					tLeftUnits = "hrs";
					tLeftString = d2s(tLeft/3600,1);
				}
				if ( (tLeft<3600)&&(tLeft>60)) {
					tLeftUnits = "min";
					tLeftString = d2s(tLeft/60,1);
				}
				if (tLeft<=60) {
					tLeftUnits = "sec";
					tLeftString = d2s(tLeft,1);
				}
				// v2.5l save results with each image to not lose progress on crash
				saveAs("Results", gImageFolder  + "0results_nAnalyses_" + gNumAnalyses +"_rois_" +gDefineNucROIs + "_" + version + "_" + startTime + ".csv");
			} // if file exists	
			print ("\\Update0: image list: " + pctDoneString + pctLeftString + " " +  (nImgsToProcess+1) + " of " + nValidImages + " lap time: " + d2s(lapTime,3) + " s, loop time: " + tLeftString + " " + tLeftUnits +" left for img set" );
		} // close skip image
    }
//need to clean up done txt files


	//set column

	setResult("Label", nResults, "gNuclearChannel"+ "|"+gNuclearChannel);
	setResult("Label", nResults, "gDefineNucROIs|"+gDefineNucROIs);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults, "gDefineNucROIs|simple threshold");	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults, "gNuclearMinArea"+ "|"+gNuclearMinArea);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults, "gBallSize"+ "|"+gBallSize);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults, "gNuclearMinArea"+ "|"+gNuclearMinArea);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults,  "nucTheshold"+ "|"+nucThreshold);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults,"gDoWaterShed"+ "|"+gDoWaterShed);	
    if (gDefineNucROIs=="simple threshold") setResult("Label", nResults,  "circThreshold"+ "|"+circThreshold);	
    if (gDefineNucROIs=="multiple thresholds") setResult("Label", nResults, "multThr params|"+gRIPAParameters);	

	chnlsCounter = 0;
	strrshp ="roi Shape"+ "|";
	strch = "channels"+ "|";
	strbs = "roiBallSize"+ "|";
	strgr = "gaussRad"+ "|";
	strrsz = "roiSize"+ "|";
	strth32 = "threshold"+ "|";
	
	for (a = 0; a<gNumAnalyses; a++) {
			strrshp = strrshp + roiShapes[a] +",";
			strch = strch + channels[a] +",";
			strbs = strbs + ballSizes[a] +",";
			strgr = strgr + gaussRadii[a] +",";
			strrsz = strrsz + roiSizes[a] +",";
			strth32 = strth32 + threshold32s[a] +",";
	}
	setResult("Label", nResults, strrshp);		
	setResult("Label", nResults, strch);		
	setResult("Label", nResults, strbs);		
	setResult("Label", nResults, strgr);		
	setResult("Label", nResults, strrsz);		
	setResult("Label", nResults, strth32);		

    gResultFileName = replace(gResultFileName,".xls","");
    gResultFileName = analyzedChannels + gResultFileName +"_"+ version;
    gResultFileName = replace(gResultFileName," ","_");
    //saveAs("Results", gImageFolder  + gResultFileName +  stamp + ".txt");
	saveAs("Results", gImageFolder  + "0results_nAnalyses_" + gNumAnalyses +"_rois_" +gDefineNucROIs + "_" + version + "_" + startTime + ".csv");


	while (isOpen("mtTable")) {
		selectWindow("mtTable");
		run("Close");
	}
	fs = File.saveString("done",donePath  + "allDone.txt");

 
	if (gDoBatchMode == true) setBatchMode("exit and display");
	print("\\Update1: Analysis of ROI intensities is complete in " + d2s((getTime-t0)/60000,2) + " min");
	run("Colors...", "foreground="+oForeGroundColor+" background="+oBackGroundColor+" selection=cyan");
    
}  //close macro

//====== MACRO END ==================================================================================================================================================



//----------------------------------------------------------------------
function processSingleImage(currAnalysisIndex, currImageName, measuredChannel, roiShape, roiSize, roiLabel, mGauss, mBallSize,threshold32b) {

    currLabelStart = nResults;
    Stack.getDimensions(width, height, channels, slices, frames) ;
    Stack.getPosition(channel, slice, frame) ;
    currSlice = slice;
    maxSD = 0;
    bestSlice = 1;
	selectWindow(currImageName);
	dupImageName = "DupOf"+currImageName;

	// if nuclear ROIset exist, skip remaking nuclear ROIs
	currImageNameForROIs = substring(currImageName,0, lastIndexOf(currImageName,"."));
	nucRoiFile = gImageFolder + items[0]+"_"+currImageNameForROIs+".zip";
	//print("looking for ROI file: "  + nucRoiFile);
	roiManager("reset"); //170122

	// ==== Open nucROI file or define nuclear ROIs ================================================================================
	if ( ( File.exists(nucRoiFile)==false) || (overwriteROIs==true) ) {
    	Stack.setChannel(gNuclearChannel);
    	Stack.getDimensions(width, height, channels, slices, frames);
		if (slices > 1) {
			bestFocusSlice(currImageName);
			Stack.getPosition(channel, slice, frame) ;
	 	    	run("Duplicate...", "title=[" + dupImageName + "] duplicate channels=" + gNuclearChannel + "  slices="+slice);
		}

		if (slices == 1) run("Duplicate...", "" + dupImageName + " duplicate channels=" + gNuclearChannel);
		getStatistics(nPixels, mean, min, max, std, histogram);
		if (gBallSize!=-1) run("Subtract Background...", "rolling="+gBallSize);   //v1.4.3
		if (mGauss!= -1) run("Gaussian Blur...", "sigma="+mGauss);

		if (gDoMultipleThresholds == false) {
			
			if ( (usRadius!=-1) ) 		run("Unsharp Mask...", "radius="+usRadius+" mask="+ usMask);  // v2.5d
			if ( (gaussRad!=-1) )	  	run("Gaussian Blur...", "sigma="+gaussRad);  // v2.6
			if (nucThreshold != -1) 	setThreshold(nucThreshold, 65555);
			if (nucThreshold == -1) 	setAutoThreshold("Default dark");
			setOption("BlackBackground", false);
			run("Convert to Mask");
			imgMask0 = getTitle();
			
			run("Analyze Particles...", "size=" + gNuclearMinArea + "-Infinity circularity=0.00-1.00 show=Masks exclude include add");
			foundNuclei = true;
			if (roiManager("count")==0) { 
				foundNuclei = false;
			} else {
				if (gDoWaterShed == true) { // to watershed based on Solidity, would have to look at each ROI, water shed, then file ROI areas if the previous ROI had a solidity above the threshold. Pretty easy. 
					if (circThreshold == 0) run("Watershed");
					if (circThreshold > 0.001) {
						run("Analyze Particles...", "  circularity=0.0-"+circThreshold+" show=Masks exclude include");
						run("Watershed");
						rename("imgMask1");
						selectWindow(imgMask0);
						run("Analyze Particles...", "  circularity="+circThreshold+0.001+"-1.0 show=Masks exclude include");
						rename("imgMask2");
						imageCalculator("Add", "imgMask2","imgMask1");
						selectWindow("imgMask1");
						close();
						selectWindow(imgMask0);
						close();
						selectWindow("imgMask2");
						rename(imgMask0);
					}
					waitForUser("done circ line 746");			
					// should be able to watershed based on solidity too by quickly measuring all ROIs. Create combine(OR) of all with solidity above some cutoff and "clear" to fill in the gaps created by watershed above.
					if (minSolid>0.001) {
						solidityIndex = newArray(0);
						nResI = nResults;
						roiManager("measure"); 
						nResF = nResults;
						ntempROIs = roiManager("count");
						for (nr = 0; nr<ntempROIs; nr++) {
							solidityNR = getResult("Solidity",nr);
							if ((solidityNR>minSolid)||(circThreshold > 0.001)) {
								solidityIndex = Array.concat(solidityIndex,nr);
							}
						}
						if (solidityIndex.length>0) {
							roiManager("select",solidityIndex);
							roiManager("Combine");
							run("Clear", "slice");
							roiManager("deselect");
							run("Select None");
						}
					}
				roiManager("reset");
				run("Analyze Particles...", "size=" + gNuclearMinArea + "-Infinity circularity=0.00-1.00 show=Masks exclude include add");
				}
				if (roiManager("count")==1) { 
					makeRectangle(0,0,2,2);
					roiManager("add");
					roiManager("select",1);
					roiManager("rename","dummy");
					roiManager("deselect");
					print("\\Update6: Only 1 nuclear ROI found. Saving extra dummy ROI to make .zip file");
				}
				
				if (roiManager("count")>0) { 
					roiManager("Save", gImageFolder + items[0]+"_"+currImageNameForROIs+".zip");
				} else {
					foundNuceli = false;
				}				
			}
			if (foundNuclei == false ) {
				print("\\Update6: No ROIs found in " + currImageNameForROIs);
			}
		}

		if (gDoMultipleThresholds == true) {
			mainTable = "mainTable";
			mtTable = "mtTable";
			currTable = "Results";
			if (isOpen("Results")) IJ.renameResults(currTable,mainTable);
			print("\\Update4: doing multiple thretholds");
			run("RIPA "+RIPAversion, gRIPAParameters);
			print("\\Update4: multiple thretholds done");
			nROIs = roiManager("count");

			if (nROIs!=0) { 
				roiManager("Save", gImageFolder + items[0]+"_"+currImageNameForROIs+".zip");
				print("\\Update4: saving " + gImageFolder + items[0]+"_"+currImageNameForROIs+".zip");
				wait(300);
// am not sure if this close call should be run("Close"); toi close a non-image window
				close();
				selectWindow("Results"); 
				IJ.renameResults(mtTable);
				selectWindow(mainTable);
				IJ.renameResults("Results");
				selectWindow(mtTable);
				run("Close");
			} else {
				print("\\Update6: No ROIs found in " + currImageNameForROIs);
				if (isOpen("Results")==true) {
					selectWindow("Results"); 
					IJ.renameResults(mtTable);
					selectWindow(mainTable);
					IJ.renameResults("Results");
					selectWindow(mtTable);
					run("Close");
				}
			}
			close("*uncta");
		}
	   	
	} else {
		roiManager("Open",nucRoiFile);
		newImage("Mask of "+dupImageName, "8-bit black", width, height, 1);
		for (iROI = 0; iROI < roiManager("count"); iROI++) { 
			roiManager("Select",iROI);
			run("Fill", "slice");
		}
		roiManager("Deselect");
	}
	
	//waitForUser(roiManager("Count") + " rois in manager");
	// ==== Analyze other cell ROI shapes of there is at least one nuclear ROI. Otherwise, skip analysis.
    if ( roiManager("Count")!=0) {
		    roiManager("Show All with labels");

			// Load OR generate specified ROI shapes ROIs
    		
			//===== option 1: analyze nuclear ROI ================================================
			if (roiShape == items[0]) {
				print("\\Update5: analyzing original nuclei");
			}
			
			if (roiShape != items[0]) {
				
				print("\\Update5: analyzing modified nuclear ROIs");
				nROIs = roiManager("count");
				
					//option 2: define boxes around center of each ROI
					 if (roiShape == items[1]) {
						if (( File.exists(""+gImageFolder + roiLabels[1]+"-"+roiSize+"_"+currImageNameForROIs+".zip")==false) || (overwriteROIs==true) ) {					 	
							for (iROI = 0; iROI < nROIs; iROI++) { 
								roiManager("Select",0);
								getSelectionBounds(x, y, width, height);
								roiManager("Delete");
								makeRectangle((x+width/2) -roiSize/2, (y+height/2)-roiSize/2, roiSize, roiSize);
								roiManager("Add");
								roiManager("select", nROIs-1);
								roiManager("Rename", roiLabels[1]+"_"+iROI);
							}
			    			roiManager("Deselect");
			    			roiManager("Save", ""+gImageFolder + roiLabels[1]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
						    roiManager("Show All with labels");
						} else {
							roiManager("reset");
							roiManager("Open",""+gImageFolder + roiLabels[1]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
						}
						
					 }
				 	//======== option 3: define "dilated nucleus" ==========================================================
					 if (roiShape == items[2]) {
					 	if (( File.exists(""+gImageFolder + roiLabels[2]+"-"+roiSize+"_"+currImageNameForROIs+".zip")==false) || (overwriteROIs==true) ) {		
							print("\\Update5: dilating nuclei");
							selectWindow("Mask of " + dupImageName);
							// new methods introduced in v1.4.8.4

							dilateROIs(roiSize);  //function
							
			    			roiManager("Save", ""+gImageFolder + roiLabels[2]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
			    			roiManager("Show All with labels");
					 	} else {
					 		roiManager("reset");
							roiManager("Open",""+gImageFolder + roiLabels[2]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
					 	}
					 }
					 
				 	//======= option 4: define "nuclear surround" - needs help. Old problem of donut ROI ====================
			  		if (roiShape == items[3]) {
			  			
			  			print("\\Update5: entered nuc surround block");
					 	if (( File.exists(""+gImageFolder + roiLabels[3]+"-"+roiSize+"_"+currImageNameForROIs+".zip")==false) || (overwriteROIs==true) ) {		
							dummy = "dummy";
							newImage(dummy, "8-bit black", width, height, 1);
							
							if (File.exists(""+gImageFolder + roiLabels[2]+"-"+roiSize+"_"+currImageNameForROIs+".zip")==true) {
								print("\\Update5: creating surrounds from existing dilated nuclei");
								roiManager("Open",""+gImageFolder + roiLabels[2]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
							} else {

								roiManager("reset");
								roiManager("Open", gImageFolder + items[0]+"_"+currImageNameForROIs+".zip");
								tStartDil = getTime();
								//nucOffSet = 3;   // v2.5f - moved to global variable.
								dilateROIs(nucOffSet);  //function
								print("\\Update5: time to dilate: " + (getTime()-tStartDil)/1000);
								roiManager("Save", ""+gImageFolder + "_inner-"+roiSize+"_"+currImageNameForROIs+".zip");
								roiManager("reset");
								roiManager("Open", gImageFolder + items[0]+"_"+currImageNameForROIs+".zip");
								tStartDil = getTime();
								dilateROIs(roiSize+nucOffSet);  //function
								print("\\Update5:  time to dilate: " + (getTime()-tStartDil)/1000);
								roiManager("Open", ""+gImageFolder + "_inner-"+roiSize+"_"+currImageNameForROIs+".zip");
								hide1 = File.delete(""+gImageFolder + "_inner-"+roiSize+"_"+currImageNameForROIs+".zip");
								//delete "inner" file
								
							}

							if (roiManager("count")%2 != 0) exit("number of nuclear ROIs != number of dilated nuclei for making surrounds");
							nCells = roiManager("count")/2;
							print("\\Update6: nCells: " + nCells);
							roiPair = newArray(0,0);
							noSurround = 0;
							for (j=0;j<nCells;j++) {
								
							    roiPair[0] = j + nCells;
								roiPair[1] = j;
								roiManager("select",roiPair);
								nROIsBefore = roiManager("count");
								roiManager("XOR");
								nROIsAfter = roiManager("count");
								
								if ((nROIsAfter - nROIsBefore)>=1) {
									roiManager("ADD");
									roiManager("select", roiManager("count")-1);
									roiManager("Rename", "surround_"+j);
								} else {
									noSurround++;
								}
							}
							
							for (j=0;j<(nCells*2-noSurround);j++) {
								roiManager("select",0);
								roiManager("Delete");
							}
							if (isOpen("dummy")) {
								selectWindow(dummy);
								close();
							}
			    			roiManager("Deselect");
			    			roiManager("Save", ""+gImageFolder + roiLabels[3]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
							roiManager("Show All with labels");
						} else {
							roiManager("reset");
							roiManager("Open",""+gImageFolder + roiLabels[3]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
					 	}
					}
					//======= option 5: define "concave hulls around nucelei"  ====================
					// steps. 
					/*- THIS MIGHT BE EASIER TO DO IN A SEPARATE SCRIPT THAT CREATES THE CONCAVE HULLS FIRST. 
					 * check if concavehull ROIs have bee created. If yes, prompt to re-use
					 * check for some measurement file that defines particle ROIs either MTO or dsDNA puncta
					 * create nuclear perimeters for current image in a separate folder 
					 * 	
					 * 	- open nuclear ROIs, call roi_Coordinates_To_File_v1.ijm to get perimeters to a predicted file
					 * 	- close nuclear ROIs
					 * 	- find particle file that matches current image. These steps could be done preemptively if roiShape == items[4] for any measures
					 * 	- 
					 */

					
					if (roiShape == items[4]) {
						if (( File.exists(""+gImageFolder + roiLabels[4]+"-"+roiSize+"_"+currImageNameForROIs+".zip")==false) || (overwriteROIs==true) ) {					 	
							for (iROI = 0; iROI < nROIs; iROI++) { 
								roiManager("Select",0);
								getSelectionBounds(x, y, width, height);
								roiManager("Delete");
								makeRectangle((x+width/2) -roiSize/2, (y+height/2)-roiSize/2, roiSize, roiSize);
								roiManager("Add");
								roiManager("select", nROIs-1);
								roiManager("Rename", roiLabels[1]+"_"+iROI);
							}
			    			roiManager("Deselect");
			    			roiManager("Save", ""+gImageFolder + roiLabels[1]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
						    roiManager("Show All with labels");
						} else {
							roiManager("reset");
							roiManager("Open",""+gImageFolder + roiLabels[1]+"-"+roiSize+"_"+currImageNameForROIs+".zip");
						}
						
					 }
					
			} // close if 	(roiShape != items[1])
		
			run("Select None");
			close("Mask of*");
			close("Dup*");
		    roiManager("Show None");
		    numberOfPart = roiManager("count");

			// ========= MEASURE ROIS FOR CURR CHANNEL ===========================================================================================
		    // ===================================================================================================================================

		    // Extract channel to be analyzed, find best focus of multiple Z, run Gauss Blur and Rolling Ball subtraction
		    selectWindow(currImageName);
		    dupImageName = substring(currImageName,0,lastIndexOf(currImageName,".")) + "_C"+measuredChannel;
		    run("Duplicate...", "title=[" + dupImageName + "] duplicate channels=" + measuredChannel);
		    selectWindow(dupImageName);
		    Stack.getDimensions(width, height, channels, slices, frames) ;
		    if (mGauss!=-1 ) run("Gaussian Blur...", "sigma="+mGauss+" stack");
		    if (slices == 1) {
				getStatistics(nPixels, mean, min, max, std, histogram);                             //v1.1  
	 			run("Subtract...", "value="+min);                                                   //v1.1
		    }
		    if (slices>1) {	
			    for (subtractingMin=1; subtractingMin<=slices;  subtractingMin++) {
					Stack.setSlice(subtractingMin);   	
					getStatistics(nPixels, mean, min, max, std, histogram);                             //v1.1  
			 		run("Subtract...", "value="+min);                                                   //v1.1
			    }
		    }
		    if (mBallSize!=-1) run("Subtract Background...", "rolling=" + mBallSize + " stack");             //v1.1   
		    if (threshold32b!=-1) {
			    run("32-bit");
				setThreshold(threshold32b, 65555);
				run("NaN Background");
		    }

		    IJ.deleteRows(currLabelStart, nResults);  // refreshes at start of function, remove any measure made in this loop so far. Possibly vestigial 160505
		    currLabelStart = nResults;
		    
		    if (slices>1) {
			    for (iCounter = 0; iCounter < numberOfPart; iCounter++) {
			        roiManager("Select", iCounter);
			        bestFocusSlice(dupImageName);
			        roiManager("Measure");
			    }
		    }
		    if (slices == 1) {
			 	roiManager("Measure");
		    }
		    run("Select None");
	    	
		    if ( (measuredChannel == gNuclearChannel) || (gPreviousImgName != currImageName) )  {
		    	gExpCellNumberStart = gUniqueCellIndex + 1;
				print("\\Update5: plan B");
		    } else {
				gUniqueCellIndex = gExpCellNumberStart-1;		    	
		    }
			gPreviousImgName = currImageName;

		    // check that channel is nuclear channel 
			if (currAnalysisIndex==0) {
				firstChannel = measuredChannel;
				firstRoiShape = roiShape;
				startCellsAnalysis1 = nResults-roiManager("count");
				endCellsAnalysis1 = nResults;
				
			}

			// dump measurements to the results table. If it appears that a given cell has already been measured, then dump measures to same row as that cell
			if (currAnalysisIndex==0) {    
			    for (iCounter = currLabelStart; iCounter < nResults; iCounter++) {
			    	cellIndex = (iCounter - currLabelStart);
			    	setResult("Label", iCounter, dupImageName + "_CELL_" + IJ.pad(cellIndex,5));
			        setResult("Channel", iCounter, measuredChannel);
			        setResult("Cell", iCounter, "" + IJ.pad(gUniqueCellIndex,5));
			        setResult("ROI shape", iCounter, roiShape);
			        gUniqueCellIndex++;
			    }
			} else {
			    for (iCounter = currLabelStart; iCounter < nResults; iCounter++) {
			    	cellIndex = (iCounter - currLabelStart);
			    	currLabel = dupImageName + "_CELL_" + IJ.pad(cellIndex,5);
			    	matchIndex = -1;
			    	for (oCounter = startCellsAnalysis1; oCounter < endCellsAnalysis1; oCounter++) {
			    		oLabel = getResultLabel(oCounter);
			    		oLabel = replace(oLabel,"_C"+firstChannel+"_","_C"+measuredChannel+"_");
			    		if (currLabel == oLabel) {
			    			matchIndex = oCounter;
			    			oCounter = endCellsAnalysis1;
			    		}
			    	}
			    	if (matchIndex != -1) {
				        setResult("Area_"+currAnalysisIndex, matchIndex, getResult("Area",iCounter));
				        setResult("Mean_"+currAnalysisIndex, matchIndex, getResult("Mean",iCounter));
				        setResult("StdDev_"+currAnalysisIndex, matchIndex, getResult("StdDev",iCounter));
				        setResult("X_"+currAnalysisIndex, matchIndex, getResult("X",iCounter));
				        setResult("Y_"+currAnalysisIndex, matchIndex, getResult("Y",iCounter));
				        setResult("IntDen_"+currAnalysisIndex, matchIndex, getResult("IntDen",iCounter));
				    	setResult("Label_"+currAnalysisIndex, matchIndex, dupImageName + "_CELL_" + IJ.pad(cellIndex,5));
				        setResult("Channel_"+currAnalysisIndex, matchIndex, measuredChannel);
				        setResult("Cell_"+currAnalysisIndex, matchIndex, "" + IJ.pad(gUniqueCellIndex,5));
				        setResult("ROI shape_"+currAnalysisIndex, matchIndex, roiShape);
				        gUniqueCellIndex++;
			    		
			    	}
			    }				
			IJ.deleteRows(currLabelStart, nResults);
			}
    } else { // close if roiManager("Count")==0
	print("\\Update6: no ROI found for img " +currImageName);

    }
    updateDisplay();
    close("Mask of*");
    close("Dup*");
    if (isOpen(dupImageName)) {
	    selectWindow(dupImageName);
    	close();
    }
    roiManager("reset");
}


// ===== EMAIL COMPOSITION =================================================================================================================================
if (doSendEmail == true) {
		// Send Email Module 2: Place at end of code once all other operations are complete
		pShellString = "$EmailFrom = \“"+usr+"\”";
		//pShellString = pShellString+"\n$EmailTo = \“dpoburko@sfu.ca\”";
		pShellString = pShellString+"\n$EmailTo = \“"+sendTo+"\”";
		pShellString = pShellString+"\n$Subject = \“"+subjectText+"\”";
		pShellString = pShellString+"\n$Body = \“"+bodyText+"\”";
		pShellString = pShellString+"\n$SMTPServer = \“smtp.gmail.com\”";
		pShellString = pShellString+"\n$SMTPClient = New-Object Net.Mail.SmtpClient($SmtpServer, 587)";
		pShellString = pShellString+"\n$SMTPClient.EnableSsl = $true";
		pShellString = pShellString+"\n$SMTPClient.Credentials = New-Object System.Net.NetworkCredential(\“"+usr+"\”, \“"+pw+"\”)";
		pShellString = pShellString+"\n$SMTPClient.Send($EmailFrom, $EmailTo, $Subject, $Body)";
		//print(pShellString);
		path =getDirectory("imagej") + "powerShellEmail.ps1";
		File.saveString(pShellString, path);
		exec("cmd", "/c", "start", "powershell.exe", path);
		hide1 = File.delete(path);
}

//----------------------------------------------------------------------
function doSetImageFolder() {
    gImageFolder = getDirectory("Select folder with images & ROIs to analyze");
    gOutputImageFolder = gImageFolder + "_ROI" + File.separator();
    gNuclearImageFolder = gImageFolder + "_NUCLEAR_ROI" + File.separator();
    gFftImageFolder = gImageFolder + "_FFT" + File.separator();
    gImageList = getFileList(gImageFolder);
    Array.sort(gImageList);
    //Array.print(gImageList);
	tempImgList = newArray(gImageList.length);
	nImgs=0;

	for (i=0; i<gImageList.length; i++) {
	    if (!(endsWith(gImageList[i], File.separator()) || endsWith(gImageList[i], "/"))) {
	        if (endsWith(gImageList[i], ".tif") || endsWith(gImageList[i], ".TIF") || endsWith(gImageList[i], ".nd2"))
	            isAnImageFile_result = true;
	            tempImgList[nImgs] = gImageList[i];
	            nImgs++;
	            //print(gImageList[i]);
	    }
	}
    gImageList = Array.slice(tempImgList, 0, nImgs);  
    gImageNumber = 0;
    gCurrentImageName = "";
}
/*------------------------------------------------------------------*/

function bestFocusSlice(img0) {

        Stack.getDimensions(width, height, channels, slices, frames) ;
        maxSD = 0;
        bestSlice = 1;
            for (sl = 0; sl<slices; sl++) {
                //run("Select None");
                Stack.setSlice( sl+1);
                getStatistics(nPixels, mean, min, max, std, histogram);
                //std = std*std/mean;
                //showMessage(std + ", " + maxSD + ", " +sl+1);
                if (std > maxSD) {
                    maxSD = std;
                    bestSlice = sl+1;
                }
            }
         Stack.setSlice(bestSlice);
}

//----------------------------------------------------------------------
function isCompositeImage() {
    _imageInformation = getImageInfo();
    _isComposite = false;
    if (indexOf(_imageInformation, "\"composite\"") >= 0)
           _isComposite = true;
    return _isComposite;
}

function isAnImageFile(fileName) {
    //check for mac and pc based path separator....
    isAnImageFile_result = false;
    if (!(endsWith(fileName, File.separator()) || endsWith(fileName, "/"))) {
        if (endsWith(fileName, ".tif") || endsWith(fileName, ".TIF") || endsWith(fileName, ".nd2"))
            isAnImageFile_result = true;
    }
    //showMessage(isAnImageFile_result + " = " + fileName);
    return isAnImageFile_result;
}

//----------------------------------------------------------------------
function getNextImage() {
	if (gImageFolder == "") {
        doSetImageFolder();
	} 
    gCurrentImageName = "";
    roi_Number = 0;
	while (gImageNumber < gImageList.length && gCurrentImageName == "") {
		gCurrentImageName = gImageList[gImageNumber];
		gImageNumber++;
        if (!isAnImageFile(gCurrentImageName))
            gCurrentImageName = "";
	} 
    return gCurrentImageName;
	//showMessage(gImageFolder + ", " +gCurrentImageName+", "+gImageList.length +","+gImageNumber);
}

function dilateROIs(roiSize) {
							
	getDimensions(width, height, channels, slices, frames);
	roiMask = "roiMask";
	imgVoronoi = "voronoi";
	imgDilated = "dilated";
	newImage(roiMask, "8-bit black", width, height, 1);
	run("Divide...", "value=255.000");
	run("16-bit");
	run("Add...", "value=1.000");
	for (j=0; j<nROIs;j++) { 
		roiManager("Select",j); //fixed in v1.4.6
		run("Multiply...", "value="+(j+1));
		run("Add...", "value=1.000");
	}
	roiManager("Deselect");
	run("Select None");
	run("Subtract...", "value=1.000");
	run("Duplicate...", "title="+imgVoronoi);
	run("Duplicate...", "title="+imgDilated);
	selectWindow(imgVoronoi);
	setThreshold(1,65555);
	run("Convert to Mask");
	run("Voronoi");
	setThreshold(1,255);
	run("Convert to Mask");
	selectWindow(imgDilated);
	setThreshold(1,65555);
	run("Convert to Mask");
	run("Invert LUT");
	run("Distance Map");
	setThreshold(0, roiSize);
	run("Convert to Mask");
	imageCalculator("Subtract", imgDilated,imgVoronoi);
	roiManager("reset");
	run("Analyze Particles...", "  show=Nothing display add");
	run("Divide...", "value=255.000");
	selectWindow(roiMask);
	for (j=0; j<roiManager("count");j++) { 
		roiManager("Select",j); //fixed in v1.4.6
		getStatistics(area, mean, min, max);
		roiManager("Rename", ""+IJ.pad(max,5)+"");
	}
	roiManager("Deselect");
	roiManager("Sort");
	run("Select None");
	selectWindow(imgVoronoi);
	close();
	selectWindow(imgDilated);
	close();
	selectWindow(roiMask);
	close();
	roiManager("Deselect");
}

function timeStamp () {
	getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
	stamp = ""+ year +""+IJ.pad(month+1,2)+""+ dayOfMonth+"-"+IJ.pad(hour,2)+""+IJ.pad(minute,2)+""+IJ.pad(second,2) ;
	return stamp;
}

function getParameterFiles() {

	//Find newest file.
	nParamFiles = 0;
	fList = getFileList(gImageFolder);
	pList = newArray(fList.length);
	pLastMod = newArray(fList.length);
	pLastMod[0] = "";
	pList[0] = "";
	for (g=0;g<fList.length;g++) {

		if (indexOf(fList[g],"0parameters")!=-1) {
			pList[nParamFiles] = fList[g];
			pLastMod[nParamFiles] = File.lastModified(gImageFolder+ File.separator+fList[g]);
			nParamFiles++;
		} else {
			pLastMod[g] = "";
			pList[g] = "";
		}
	}
	print("\\Update0: nParamFiles = " + nParamFiles);
	if (nParamFiles==0){
		pList = Array.slice(pList,0,2);
	}
	if (nParamFiles==1){
		pFile = pList[1];
		pList = Array.slice(pList,0,1);
	}
	
	if (nParamFiles>1) {	
	//Array.print(pList);
		pList = Array.slice(pList, 0, nParamFiles);
	//Array.print(pList);
		pLastMod = Array.slice(pLastMod, 0, nParamFiles);
		ranks = Array.rankPositions(pLastMod);
		Array.getStatistics(ranks, min, max, mean, stdDev);
		for (i = 0; i < ranks.length; i++) {
			if (ranks[i] == max) newest = i;
		}
		pFile = pList[newest];
	} 
	//print("parameters files list");
	//Array.print(pList);
	return pList;
}



function getParameters() {

	gDoBatchMode = false;
	doSendEmail = false;
	clearFlags = false;
	slices2channels = false;

	for(i=0;i<nResults;i++) {
		
		parameter = getResultString("Parameter",i);
		value =  getResultString("Values00",i);
		//print("parameter: " +parameter+ " Value: "+value);
		if (parameter == "gNuclearChannel") gNuclearChannel = value; 
		if (parameter == "gNumAnalyses") gNumAnalyses = value; 
		if (parameter == "gDefineNucROIs") gDefineNucROIs = value; 
		if (parameter == "gDoBatchMode")gDoBatchMode = value; 
		if (parameter == "doSendEmail") doSendEmail = value; 
		if (parameter == "clearFlags") clearFlags = value; 
		if (parameter == "slices2channels") slices2channels = value; 
		if (parameter == "roiShapes") roiShapes = split(replace(value," ",""),","); 
		if (parameter == "channels") channels = split(replace(value," ",""),","); 
		if (parameter == "ballSizes") ballSizes = split(replace(value," ",""),","); 
		if (parameter == "gaussRadii") gaussRadii = split(replace(value," ",""),","); 
		if (parameter == "roiSizes") roiSizes = split(replace(value," ",""),","); 
		if (parameter == "threshold32s") threshold32s = split(replace(value," ",""),","); 

		//defining ROI parameters
		if (parameter == "define_Nuc_ROIs") define_Nuc_ROIs = value; 
		if (parameter == "simpleThreshold") simpleThreshold = value; 
		if (parameter == "gBallSize") gBallSize = value; 
		if (parameter == "gNuclearMinArea") gNuclearMinArea = value; 
		if (parameter == "gBallSize") gBallSize = value; 
		if (parameter == "nucThreshold") nucThreshold = value; 
		if (parameter == "usRadius") usRadius = value; 
		if (parameter == "usMask") usMask = value; 
		if (parameter == "gDoWaterShed") gDoWaterShed = value; 
		if (parameter == "circThreshold") circThreshold = value; 
		if (parameter == "minSolid") minSolid = value; 
		if (parameter == "gaussRad") gaussRad = value; 
		if (parameter == "overwriteROIs") overwriteROIs = value; 
		if ((parameter == "clearFlags")&& (value==1)) clearFlags = true; 
		if ((parameter == "gDoBatchMode")&& (value==1)) gDoBatchMode = true; 
		if ((parameter == "doSendEmail")&& (value==1)) doSendEmail = true; 
		
		//need to add values for when ROIs are defined by multiple thresholds

		
	}
	
 	call("ij.Prefs.set", "dialogDefaults.gNuclearChannel",gNuclearChannel);
 	call("ij.Prefs.set", "dialogDefaults.gNumAnalyses",gNumAnalyses);
 	call("ij.Prefs.set", "dialogDefaults.gDefineNucROIs",gDefineNucROIs);
 	call("ij.Prefs.set", "dialogDefaults.gDoBatchMode",gDoBatchMode);
 	call("ij.Prefs.set", "dialogDefaults.doSendEmail",doSendEmail);
 	call("ij.Prefs.set", "dialogDefaults.clearFlags",clearFlags);
 	call("ij.Prefs.set", "dialogDefaults.slices2channels",slices2channels);

 	//call("ij.Prefs.set", "dialogDefaults.define_Nuc_ROIs",define_Nuc_ROIs);
 	call("ij.Prefs.set", "dialogDefaults.gBallSize",gBallSize);
 	call("ij.Prefs.set", "dialogDefaults.gNuclearMinArea",gNuclearMinArea);
 	call("ij.Prefs.set", "dialogDefaults.gBallSize",gBallSize);
 	call("ij.Prefs.set", "dialogDefaults.nucThreshold",nucThreshold);
 	call("ij.Prefs.set", "dialogDefaults.gaussRad",gaussRad);
 	call("ij.Prefs.set", "dialogDefaults.usRadius",usRadius);
 	call("ij.Prefs.set", "dialogDefaults.usMask",usMask);
 	call("ij.Prefs.set", "dialogDefaults.gDoWaterShed",gDoWaterShed);
 	call("ij.Prefs.set", "dialogDefaults.circThreshold",circThreshold);
 	call("ij.Prefs.set", "dialogDefaults.minSolid",minSolid);
 	call("ij.Prefs.set", "dialogDefaults.overwriteROIs",overwriteROIs);

	for(i=0;i<roiShapes.length-1;i++) {
 			
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"shape",roiShapes[i]);
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"channel",channels[i]);
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"ballSize",ballSizes[i]);
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"gausRadii",gaussRadii[i]);
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"roiSize",roiSizes[i]);
 		call("ij.Prefs.set", "dialogDefaults.c"+(i+1)+"threshold32",threshold32s[i]);
	}
}


	