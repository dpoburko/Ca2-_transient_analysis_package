//Created by Damon Poburko at Simon Fraser University, ca. Dec. 2016. Contact at dpoburko@sfu.ca


	dir = getDirectory("Choose a Directory ");
	mainList = getFileList(dir);
	mainList = Array.sort(mainList);


	imgList = newArray(mainList.length);
	nImgs = 0;
	overWrite = false;

setBatchMode(true);
t0 = getTime;

	for ( i =0; i< mainList.length; i++) {
		if ( ( endsWith(mainList[i], ".tif") == true) || ( endsWith(mainList[i], ".nd2") == true))  {
			imgList[nImgs] = mainList[i];
			nImgs++;
		}
	}
	imgLis = Array.trim(imgList,nImgs);

	outputDir = "bleachCorrected"; 
	outputDirPath = dir + outputDir;
	if (File.exists(outputDirPath)==false) 	File.makeDirectory(outputDirPath);

	for (a=0; a<nImgs; a++) {
		
		t1 = getTime;
		open(dir + imgList[a]);
		img0 = getTitle();
		print("\\Update1: opening img " + a + " of " + nImgs);
		img0 = getTitle();
		dblExpCorrect(img0);
		img1 = substring(img0, 0,indexOf(img0,"."));
		saveAs("Tiff", outputDirPath + File.separator + img1);
		close();
					lapTime = (getTime() - t1)/1000;
					t1 = getTime();
					tLeft =   (  (t1-t0) / (a+1) ) * (nImgs-a)  / 1000 ;
					//selectWindow(pBar);
					progress = ( a + 1)/nImgs ;

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
					
					print ("\\Update4: curr Img: " + pctDoneString + pctLeftString + " " +  (a+1) + " of " + nImgs + " loop time: " + d2s(lapTime,3) + " s");



	}

setBatchMode("exit and display");

//step 1: fit to biexponential
//get paramters and correct


//sttep 2: fit to line, and correct
//print("\\Clear");
function dblExpCorrect(img0) {
		
		startSlice= getSliceNumber();
		Stack.getDimensions(width, height, channels, slices, frames);
		setSlice(1);
		makeRectangle(0, 0, width, height);	//select entire image as ROI
		getStatistics(area, mean, min, max, std, histogram); //get mean of first frame
		
		//get time profile over whole field
		run("Plot Z-axis Profile");
		plot = getTitle();
		Plot.getValues(x, y);
		selectWindow(plot);
		close();
		run("Select None");
		selectWindow(img0);
		
		//fit to double exponential
		  dblExpDecay = "y = a*exp(b*x) + c*exp(d*x)";
		  a = mean*0.1; b = -0.01; c = mean*0.9; d = -0.002;
		  initialGuesses = newArray(a, b, c, d);
		  Fit.doFit(dblExpDecay, x, y, initialGuesses);
		  Fit.logResults;
		  //Fit.plot();
		  Fit.logResults;
		  r2 = Fit.rSquared;
		  
		selectWindow(img0);
		
		for (s=1; s<=nSlices(); s++) {
			setSlice(s);
			getStatistics(area, mean2);
			//corrFactor = mean / (a*exp(b*s) + c*exp(d*s));
			//corrFactor = mean / Fit.f(s-1);
			corrFactor = Fit.f(0) / Fit.f( x[s-1]);
			run("Multiply...", "value="+corrFactor+" slice");
		}
		return(true);
}



//makeRectangle(0, 0, width, height);	//select entire image as ROI
//run("Plot Z-axis Profile");
