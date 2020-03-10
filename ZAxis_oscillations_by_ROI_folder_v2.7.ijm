/* 
 * Created by Damon Poburko at Simon Fraser University, ca. Dec. 2016. Contact at dpoburko@sfu.ca
 * DP - 180206: Need to add a functionality to measure correlation of signal between N nearest neighbours. Report min mean max corr value and min mean max dist to neighbours - done
 * DP - 180803: add option to creat plot of ROI "x" with trace and peaks as separate results table. Just add option to save plots as csv files. 
 * 
 */

var doFolder = true;
var	doPlot = false;
var batchMode = true;
var plotROIs = "24"; //comma separated list of ROIs to plot
var	pkFitMaxTolerance = 0.03;
var	maxFFTPeriod = 15;
var	FFTPeakToleranceFraction = 0.03;
var	returnArrayLabels = newArray("nPeaks","tPk2PkMean", "tPk2PkSD", "pkHeightMean", "pkHeightSD","baselineMean", "baselineSD","fwhmMean", "fwhmSD", "decayConstMean", "decayConstSD", "gaussr2Mean", "gaussr2SD","expr2Mmean", "expr2SD","preferredModelMean", "perMain", "amplMain","per2", "ampl2","tPeak0","tPeak1"); 
var	nParameters = returnArrayLabels.length;
var	returnArray = newArray(nParameters);
var img0 = "";
var totalROIs = 0;
var nFrames = 0;
var numNN = 1;
var minPksAnalyzed = 1;
     

run("Set Measurements...", "area mean standard min centroid center shape redirect=None decimal=3");



//parse folder for images and ROIs
if (doFolder==true) {	
	dir = getDirectory("Choose a Directory ");
	mainList = getFileList(dir);
	Array.sort(mainList);
	imgList = newArray(mainList.length);
	roiList = newArray(mainList.length);
	nImgs = 0;
	nRoisSets = 0;
	fTypesAllowed = newArray(".tif",".TIF",".tiff",".TIFF",".lsm",".nd2");

	lastFolder = split(dir,File.separator);
	lastFolder = lastFolder[lastFolder.length-1];
	

	doSendEmail= false;
	  html = "<html>"
	     +"<h2>Windows requirement for sending email via ImageJ</h2>"
    	 +"<font size=+1>
     	+"run powershell.exe as an administator"
	     +"To do this: Type powershell.exe in windows search bar"
    	 +"... right click and select Run as Administrator"
	     +"type: 'Set-ExecutionPolicy RemoteSigned' "
    	 +"</font>";
  
		// Send Emamil Module 1: Place near beginning of code. Might want as an extra option after first dialog
		Dialog.create("Email password - Cancel to skip");
		Dialog.addCheckbox("Send email.",true);
		Dialog.addMessage("Security Notice: User name and password will not be stored for this operation");
		Dialog.addString("Gmail address to send email - joblo@gmail.com", "polabsfu@gmail.com",60);
		Dialog.addString("Password for sign-in", "password",60);
		Dialog.addString("Email notification to:", "dpoburko@sfu.ca",60);
		Dialog.addString("Subject:", ""+ lastFolder +" Z-Axis Oscillations Analysis Complete",70);
		Dialog.addString("Body:", "Folder "+lastFolder+" is done.",70);
		Dialog.addHelp(html);
		Dialog.show();
		
		doSendEmail = Dialog.getCheckbox;
		usr = Dialog.getString();
		pw = Dialog.getString();
		sendTo = Dialog.getString();
		subjectText = Dialog.getString();
		bodyText = Dialog.getString();

	
	//parse mainlist of files to create sets of images and ROI files
	//create list of images of specified type that match template
	for (i=0; i<mainList.length; i++) {
		if ( (endsWith(mainList[i], "/")==false) && (endsWith(mainList[i], File.separator() )==false ) ) { 
			fType = substring(mainList[i], lastIndexOf(mainList[i], "."), lengthOf(mainList[i]));
			fTypeOK = false;
			for (k = 0; k<fTypesAllowed.length; k++) {
				if (fType ==  fTypesAllowed[k]) 	fTypeOK = true;
			}
			//find potential images		
			if (fTypeOK == true) {
				
				//check for matched ROI files
				foundMatchedROIs = false;
				for (j=0; j<mainList.length; j++) {
					imgBaseName = 	toUpperCase(substring(mainList[i],0,indexOf(mainList[i],".")));
					//print("image basename: " + imgBaseName);
					if ( (endsWith(mainList[j], ".zip")==true) && ( indexOf(toUpperCase(mainList[j]),imgBaseName)>-1 ) ) {
						//print("matched ROIs: " + mainList[j]);
						imgList[nImgs] = mainList[i];
						roiList[nImgs] = mainList[j];
						nImgs++;
					}
				}
				
			}
		}
    }
    nROIsets = nImgs;
	imgList = Array.trim(imgList,nImgs);
	roiList = Array.trim(roiList,nImgs);

setBatchMode(batchMode);
print("\\Clear");
t0 = getTime();

// loop through list of images with ROIs
for (imgIndex=0; imgIndex<imgList.length;imgIndex++) {
	
	t1 = getTime();
	print("\\Update6: img "+imgIndex+" " + dir + imgList[imgIndex]);
	open(dir + imgList[imgIndex]);
	img0 = getTitle;
	Stack.getDimensions(width, height, channels, slices, nFrames);
	currBaseName = substring(img0,0,indexOf(img0,"."));
	
	Stack.getStatistics(voxelCount, mean, min, max, stdDev);
	run("Subtract...", "value="+min+" stack");
	roiManager("reset");
	//print("opening " + dir + roiList[imgIndex]);
	roiManager("Open", dir + roiList[imgIndex]);

	//Call to main analysis function
	analyzeROIs();

	
	selectWindow(img0);
	close;
	selectWindow("mainTable");
	IJ.renameResults("Results");
	
	
	saveAs("Results", dir  + File.separator + currBaseName +  "_zProfile.txt");	
	if (File.exists(dir  + File.separator + currBaseName +  "_zProfile.txt")==true ) {
		print("\\Update7: Results saved for img " + (imgIndex+1) + " of " + nImgs + ": " + img0 );
		
	
		 
	} else {
		print("\\Update7: Results NOT saved for " + img0);
	}
	run("Clear Results");
	print("\\Update0: Lap time:  " + d2s((getTime()-t1)/60000,1) + " min. " + (imgIndex+1) + " of " + nImgs + ": " + img0 );
    print("\\Update1: est. time left:  " + d2s((nImgs-imgIndex+1)*((getTime()-t0)/60000)/(imgIndex+1),1) + " min");

}
	print("\\Update0: analysis complete in " + (getTime()-t0)/60000 + " min");

setBatchMode("exit and display");

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
	
function analyzeROIs() {

	mainTable = "mainTable";

	//load all Z-profiles into one giant 1D array. Then calc N nearest neighbours. And for each, calc correlation coeff of each. 
	nROIs =roiManager("count");
	bigHolder = newArray(nParameters * nROIs);
	roiHasGt1Pk = newArray(nROIs);
	for (roi=0; roi<nROIs;roi++) {
		print("\\Update2: Part I - roi "+roi+" / " + nROIs);
		selectWindow(img0);
		roiManager("select",roi);
		returnArray = findPeaks(pkFitMaxTolerance,maxFFTPeriod,FFTPeakToleranceFraction,returnArray,doPlot,plotROIs);
		// v2.5 - exclude ROIs as NN if they have less than 2 pks.
		if (returnArray[0] > 2) {
			roiHasGt1Pk[roi] = 1;
		} else {
			roiHasGt1Pk[roi] = 0;
		}
		selectWindow(img0);	
		//collect all Z-axids profiles into a single 1D array for subsequent correlation analysis
		run("Plot Z-axis Profile");
		plot = getTitle();
		Plot.getValues(x2, Y2);
		selectWindow(plot);
		close();
		if (roi == 0) {
			zProfilesBin = Y2;
		} else {
			zProfilesBin =  Array.concat(zProfilesBin,Y2);
		}
		for(param=0; param<nParameters; param++) {
			bigHolder[(roi*nParameters)+param] = returnArray[param];
		}
	}
	//print("\\Update8: roiHasGt1Pk");
	//Array.print(roiHasGt1Pk);

	//close Results window from oscillations analysis
	if (isOpen("Results")) {
		selectWindow("Results"); 
		run("Close");
	}

	// find N nearest neighbours to each ROI.
	
	nnIndicies = newArray(numNN * nROIs);
	nnDistancesAll= newArray(numNN * nROIs);
	nnCorrCoefs= newArray(numNN * nROIs);
	nnDistances = newArray(nROIs);
	roiManager("deselect");
	roiManager("measure");
	
	//collect XY coordinates of each nucleus
	nucXs = newArray(nROIs);
	nucYs = newArray(nROIs);
	for (roi=0; roi<nROIs;roi++) {
		if (roiHasGt1Pk[roi] == 0) {
			// If roi has less than 2 identified peaks, set it's XY coordinates to be some obsurd value, which will effectively 
			// prevent it from being viewed as a nearest neighbour to any cell with >= 2 peaks. 
			nucXs[roi] = 50000;
			nucYs[roi] = 50000;
		} else {
			nucXs[roi] = getResult("X",roi);
			nucYs[roi] = getResult("Y",roi);
		}
		
	}
	//print("Update\\8: nucXs & Ys");
	//Array.print(nucXs);
	//Array.print(nucYs);
	//waitForUser;

	//holders for correlation coefficients
	rMeans = newArray(nROIs);
	rMaxs = newArray(nROIs);
	rMins = newArray(nROIs);
	rSDs = newArray(nROIs);
	minNNDs = newArray(nROIs);
	maxNNDs = newArray(nROIs);
	meanNNDs = newArray(nROIs);
	minRMSE  = newArray(nROIs);
	maxRMSE  = newArray(nROIs);
	meanRMSE  = newArray(nROIs);

	//calculate distance between curr ROI and all others each pair
	for (a=0; a<nROIs;a++) {
		print("\\Update2: Part II - roi "+roi+" / " + nROIs);
		for (b=0; b<nROIs;b++) {
			//nnDistances[b] = 50000;
			nnDistances[b] = sqrt( pow(nucXs[a]-nucXs[b],2) + pow(nucYs[a]-nucYs[b],2));
		}
		sortedNNIndex = Array.getSequence(nROIs);  //start with a sequence of integers, then sort by NN distances
		nnDistances2 =nnDistances;             // copy of nnDistances to be sorted
		sort_B_by_sortedA(nnDistances2,sortedNNIndex); //ranks nnDistances and sorts indicies by sort order. Creates sorted list of ROI number by NN distance
		sortedDistances = Array.sort(nnDistances);

		//Z-axix of curr ROI is kept in zProfilesBin. Extra based on current array indices
		currZProfile = Array.slice(zProfilesBin, nFrames*a,nFrames*a + nFrames-1);

		correlCoefBin = newArray(numNN);
		nnDistBin =  newArray(numNN);

		//Array.print(sortedDistances);
		nnDistancesCurr = Array.slice(sortedDistances, 1, numNN);
		
		Array.getStatistics(nnDistancesCurr,minNNDs[a], maxNNDs[a], meanNNDs[a],stdev);
		print("\\Update9: roiHasGt1Pk " + roiHasGt1Pk[a] + " minNND " + minNNDs[a] + " maxNND " + maxNNDs[a] + " meanNND " + meanNNDs[a]);
		nnRMSEs = newArray(numNN);

		for (n = 0; n<numNN; n++) {
			nnIndicies[ a*numNN + n] = sortedNNIndex[n+1];
			print("\\Update3: NN is " + sortedNNIndex[n+1]);
			nnDistancesAll[ a*numNN + n] = nnDistances2[n+1];
			// Pull Z-profile arrays for curr ROI and N nn
			nextZProfile = Array.slice(zProfilesBin, nFrames*sortedNNIndex[n+1],nFrames*sortedNNIndex[n+1] + nFrames-1);
			
			
			//fit line for two profiles & get correlation coefficienct
			Fit.doFit("Straight Line", currZProfile, nextZProfile);
			correlCoefBin[n] = Fit.rSquared;

			//RMSE: calculate difference as fractinal root mean square error
			SS = 0;
			for (f=0 ; f < nFrames-1; f++) {
				Array.getStatistics(currZProfile,min, max, meanCurrZ,stdev);
				Array.getStatistics(nextZProfile,min, max, meanNextZ,stdev);
				SS = SS + pow( (currZProfile[f]/meanCurrZ) - (nextZProfile[f]/meanNextZ) ,2);
			}
			nnRMSEs[n] = sqrt( SS/nFrames);
			
		}
		Array.getStatistics(correlCoefBin, rMins[a], rMaxs[a], rMeans[a], rSDs[a]);
		Array.getStatistics(nnRMSEs, minRMSE[a], maxRMSE[a], meanRMSE[a], stdev);
		print("\\Update4: " + numNN + " NN, r=" + rMeans[a] + " mean dist: " + meanNNDs[a]);
	}

	//close Results window from oscillations analysis
	selectWindow("Results"); 
	run("Close");
	
	if (isOpen(mainTable)==true) {
		selectWindow(mainTable);
		IJ.renameResults("Results");
	}
	//copy results to table
	selectWindow(img0);		
	lastRow = nResults;
	roiManager("deselect");
	roiManager("measure");
	
	
	//load oscillation parameters from bigHolder into mainTable
	for (roi=0; roi<nROIs;roi++) {
		for(param=0; param<nParameters; param++) {
			row = roi + lastRow;	
			setResult(returnArrayLabels[param], row, bigHolder[(roi*nParameters)+param]);
		}

		setResult("rMin", row, rMins[roi]);
		setResult("rMax", row, rMaxs[roi]);
		setResult("rMean", row, rMeans[roi]);
		setResult("rSD", row, rSDs[roi]);
		setResult("minNNd", row, minNNDs[roi]);
		setResult("maxNNd", row, maxNNDs[roi]);
		setResult("meanNNd", row, meanNNDs[roi]);
		setResult("minRMSE", row, minRMSE[roi]);
		setResult("maxRMSE", row, maxRMSE[roi]);
		setResult("meanRMSE", row, meanRMSE[roi]);

	}
	
	selectWindow("Results");
	IJ.renameResults(mainTable);
	totalROIs = totalROIs + nROIs;
	
}	
	

function findPeaks(pkFitMaxTolerance,maxFFTPeriod,FFTPeakToleranceFraction,returnArray, doPlot, plotROIs ) {	

	doPlot = doPlot;
	pkFitMaxTolerance = pkFitMaxTolerance;
	maxFFTPeriod = maxFFTPeriod;
	FFTPeakToleranceFraction = FFTPeakToleranceFraction;

	run("Plot Z-axis Profile");
	plot = getTitle();
	Plot.getValues(x, Ys);


	//Part1: Fit individual peaks
	//===============================================================================
	//===============================================================================
	len = Ys.length;
	acqFreq = 1; // sampling frequency in Hz
	  frequ=len/acqFreq;       //cycles per array length
	  windowType="None"; //None, Hamming, Hann or Flattop
	t = Array.copy(x);
	for (k=0; k<x.length;k++) {
		t[k] = x[k]/acqFreq;
	}
	
	selectWindow(plot);
	close;
	Array.getStatistics(Ys, YsMin, YsMax, YsMean, YsStdDev); 
	rawRange = YsMax-YsMin;
	rawTolerance = YsMin*pkFitMaxTolerance;
	//rawTolerance = 0.03
	// find Maxima in trace
	rawMaxLocs = Array.findMaxima(Ys,rawTolerance);
	xRawMaxima = newArray(rawMaxLocs.length);
	yRawMaxima = newArray(rawMaxLocs.length);
	for (jj= 0; jj < rawMaxLocs.length; jj++){
		xRawMaxima[jj]= t[rawMaxLocs[jj]];
		yRawMaxima[jj] = Ys[rawMaxLocs[jj]];
  	}
  	
  	//find Minima in trace
  	rawMinLocs = Array.findMinima(Ys,rawTolerance);
	xRawMinima = newArray(rawMinLocs.length);
	yRawMinima = newArray(rawMinLocs.length);
	for (jj= 0; jj < rawMinLocs.length; jj++){
		xRawMinima[jj]= t[rawMinLocs[jj]];
		yRawMinima[jj] = Ys[rawMinLocs[jj]];
  	}

	//sort maxima by X
	rankPosArr = Array.rankPositions(xRawMaxima);
	ranks = Array.rankPositions(rankPosArr);
	xTemp = Array.copy(ranks);
	yTemp = Array.copy(ranks);
	for (k=0;k<xRawMaxima.length;k++) {
		xTemp[ranks[k]] = xRawMaxima[k];
		yTemp[ranks[k]] = yRawMaxima[k];
	}
	xRawMaxima = xTemp;
	yRawMaxima = yTemp;

	
	//sort minima by X
	rankPosArr = Array.rankPositions(xRawMinima);
	ranks = Array.rankPositions(rankPosArr);
	
	xTemp = Array.copy(ranks);
	yTemp = Array.copy(ranks);
	for (k=0;k<xRawMinima.length;k++) {
		xTemp[ranks[k]] = xRawMinima[k];
		yTemp[ranks[k]] = yRawMinima[k];
	}
	xRawMinima = xTemp;
	yRawMinima = yTemp;

	if (doPlot == true) {
		Plot.create("Raw trace", "time (s)", "AFU", t, Ys);
		Plot.setColor("red","red");
	  	Plot.setLineWidth(5);
		if (rawMaxLocs.length != 0) Plot.add("circles",xRawMaxima,yRawMaxima);
		Plot.setLineWidth(1);
		if (rawMaxLocs.length != 0) Plot.add("line",xRawMaxima,yRawMaxima);
		Plot.setColor("blue","blue");
	  	Plot.setLineWidth(5);
		if (rawMinLocs.length != 0) Plot.add("circles",xRawMinima,yRawMinima);
		Plot.setLineWidth(1);
		if (rawMinLocs.length != 0) Plot.add("line",xRawMinima,yRawMinima);
		Plot.setColor("black");
		Plot.setLineWidth(1);
		Plot.add("line",t,Ys);
		Plot.setFontSize(16);
		Plot.show();
	}

	nExp =0;
	nGauss = 0;
	tPeak0 = -1;
	tPeak1 = -1;
	nPeaks = xRawMinima.length-1;

	//v2.5 temporatilly broke this to run faster
	if (nPeaks>minPksAnalyzed) {	
	//if (nPeaks>0) {	
		firstMaximaUsed = 0;
		if (xRawMaxima[0] < xRawMinima[0]) firstMaximaUsed = 1;
	
		print("\\Update5: nPeaks = " + nPeaks);
		if (xRawMaxima[xRawMaxima.length-1] < xRawMinima[xRawMinima.length-1]) nPeaks = xRawMinima.length-2;

		//dataHolders for each peak
		preferredModel = newArray(nPeaks);
		Array.fill(preferredModel,-1);
		fitParam1 = Array.copy(preferredModel);
		fitParam2 = Array.copy(preferredModel);
		fitParam3 = Array.copy(preferredModel);
		fitParam4 = Array.copy(preferredModel);
		fitParam5 = Array.copy(preferredModel);
		fitParam6 = Array.copy(preferredModel);
		Array.fill(fitParam6,1);
		fitParam7 = Array.copy(preferredModel);
		expr2 = Array.copy(preferredModel);
		gaussr2 = Array.copy(preferredModel);
		pkHeight =  Array.copy(preferredModel);
		tPk2Pk =  Array.copy(preferredModel);

		for (p = 0; p<nPeaks; p++) {
	
			//fit gaussian
			for (tt= 0; tt< t.length; tt++) {
				if(t[tt]<=xRawMinima[p]) tIndex1 = tt;
				if(t[tt]<=xRawMinima[p+1]) tIndex2 = tt;
				if(t[tt]<=xRawMaxima[p+firstMaximaUsed]) tIndexPk = tt;
			}
			if (p==0) tPeak0 = xRawMaxima[p+firstMaximaUsed];
			if (p==1) tPeak1 = xRawMaxima[p+firstMaximaUsed];
			
			if (p>0) {
				tPk2Pk[p] = xRawMaxima[p+firstMaximaUsed] - tPkPrevious;				
			}
			tPkPrevious = xRawMaxima[p+firstMaximaUsed];
			
			//Gauss fit
			if ( (tIndex2 - tIndexPk+1)>=3) {
				gauss = "y = a + (b-a)*exp(-(x-c)*(x-c)/(2*d*d))";
					gA = yRawMinima[p];
					gB = yRawMaxima[p]-yRawMaxima[p];
					gC = xRawMaxima[p];
					gD = (xRawMinima[p+1]-xRawMinima[p])/2 ;
					gaussGuess = newArray(gA,gB,gC,gD);
				gaussXs = Array.slice(t,tIndex1,tIndex2);
				gaussYs = Array.slice(Ys,tIndex1,tIndex2);
				Fit.doFit(gauss, gaussXs, gaussYs,gaussGuess);
				fitParam1[p] = Fit.p(0); 
				fitParam2[p] = Fit.p(1); 
				fitParam3[p] = Fit.p(2); 
				fitParam4[p] = Fit.p(3)*2.35; 
				gaussr2[p] = Fit.rSquared;
			}
			//Exponental fit parameters	
			if ( (tIndex2 - tIndexPk+1)>=3) {
				expDecay = "y = a*exp(b*(x)) + c";
					eA = Ys[tIndexPk+1] - Ys[tIndex2];
					eB = -1.5;
					eC = Ys[tIndex2];
					expGuess = newArray(eA,eB,eC);
				expXs = Array.slice(t,tIndexPk+1,tIndex2);
				expYs = Array.slice(Ys,tIndexPk+1,tIndex2);
				for (xx=0; xx<expXs.length;xx++) {
					expXs[xx] = expXs[xx] - t[tIndexPk+1];
				}
				Fit.doFit(expDecay, expXs, expYs,expGuess);
				fitParam5[p] = Fit.p(0); 
				fitParam6[p] = Fit.p(1); 
				fitParam7[p] = Fit.p(2); 
				expr2[p] = Fit.rSquared;
	
			}
			
			if (expr2[p]>gaussr2[p]) { 
				preferredModel[p] = 1;
				nExp = nExp + 1;
			} else {
				preferredModel[p] = 0;
				nGauss = nGauss + 1;
			}
			pkHeight[p] =  Ys[tIndexPk] - (Ys[tIndex1]+Ys[tIndex2])/2;
	
		}
		
		if (tPk2Pk.length>1) { 
			tPk2Pk = Array.trim(tPk2Pk,xRawMaxima.length-1);
			Array.getStatistics(tPk2Pk,min, max, tPk2PkMean, tPk2PkSD);

		} else {

			tPk2PkMean = -1;
			tPk2PkSD = -1;
		}
		Array.getStatistics(pkHeight,min, max, pkHeightMean, pkHeightSD);
		Array.getStatistics(preferredModel,min, max, preferredModelMean, preferredModelSD);
		Array.getStatistics(yRawMinima,min,max,baselineMean,baselineSD);
	
		for (kk = 0; kk<fitParam4.length;kk++){
			if (preferredModel[kk]==1) {
				fitParam4[kk] = 0;
			} else {
				fitParam6[kk] = 0;
			}
		}
		//Collect stats on exponential vs gaussian peaks;
		if (nGauss>0) {
			preferredFitParam4 = Array.trim(Array.reverse(Array.sort(fitParam4)),nGauss);
			Array.getStatistics(preferredFitParam4, min, max, fwhmMean, fwhmSD); // gauss FWHM
			preferredGaussr2 = Array.trim(Array.reverse(Array.sort(gaussr2)),nGauss);
			Array.getStatistics(preferredGaussr2, min, max, gaussr2Mean, gaussr2SD); // gauss FWHM
		} else {
			fwhmMean =-1;
			fwhmSD = -1;
			gaussr2Mean =-1;
			gaussr2SD = -1;
		}
		if (nExp>0) {
			preferredFitParam6 = Array.trim(Array.sort(fitParam6),nExp);
			Array.getStatistics(fitParam6, min, max, decayConstMean, decayConstSD); // gauss FWHM
			preferredExpr2 = Array.trim(Array.sort(expr2),nExp);
			Array.getStatistics(preferredExpr2, min, max, expr2Mean, expr2SD); // gauss FWHM
		} else {
			decayConstMean = -1; 
			decayConstSD = -1;
			expr2Mean =-1;
			expr2SD = -1;
		}
	
	
		
	} else {   	// ***** end if nPeaks < 0  ************
		
		// no Peaks found, set all parameters other than baseline to -1
		tPk2PkMean = -1;
		tPk2PkSD = -1;	
		pkHeightMean = -1;
		pkHeightSD = -1;
		preferredModelMean = -1;
		preferredModelSD = -1;
		fwhmMean =-1;
		fwhmSD = -1;
		gaussr2Mean =-1;
		gaussr2SD = -1;
		decayConstMean = -1; 
		decayConstSD = -1;
		expr2Mean =-1;
		expr2SD = -1;
		Array.getStatistics(Ys,min,max,baselineMean,baselineSD);
	}
	
	
	Ysqrd = newArray(lengthOf(Ys));  
	for (i=0; i<lengthOf(Ys); i++) {
		Ysqrd[i] = (Ys[i]-YsMin)*(Ys[i]-YsMin);	
	}
	Array.getStatistics(Ysqrd, YsqrdMin, YsqrdMax, YsqrdMean, YsqrdStdDev); 
	rawRMS = sqrt(YsqrdMean);
	
	
	//Part2: FFT analysis of temporal plot 
	//===============================================================================
	//===============================================================================

	//y = Array.fourier(a, windowType);
	y = Array.fourier(Ys);
 	f = newArray(lengthOf(y));
	for (i=0; i<lengthOf(y); i++) {
		a = lengthOf(y)-i;
		f[i] = 1- (a/ lengthOf(y));
	}
	for (ff =0; ff<f.length; ff++) {
		if (f[ff] > 1/maxFFTPeriod) {
			peaksOffset = ff;
			ff  =	f.length;
		}
	}
	
	//find maxima in FFT power spectra
	ySliced = Array.slice(y,peaksOffset,y.length);
	fSliced = Array.slice(f,peaksOffset,f.length);
	// peak-to-peak amplitude of sin wave is ~2.8*RMS
	//FFTPeakToleranceFraction = 0.05;   //moved to start for inclusion as function
	tolerance = FFTPeakToleranceFraction*y[0]/2.8;
	maxLocs = Array.findMaxima(ySliced,tolerance);
	if (maxLocs.length == 0) {
		freqMain = -1;
		perMain = -1;
		amplMain = -1;
		per2 = -1;
		ampl2 = -1;
		
	} else {
		xMaxima = newArray(maxLocs.length);
		yMaxima = newArray(maxLocs.length);
		nMaxima = 0;
		for (jj= 0; jj < maxLocs.length; jj++){
				tempYmax = y[maxLocs[jj]+peaksOffset];
			//tempYmax = y[maxLocs[jj]+peaksOffset] + 0.5*y[maxLocs[jj]+peaksOffset-1]+ 0.5*y[maxLocs[jj]+peaksOffset+1];
			if ( tempYmax*2.8 <= rawRange) {
				xMaxima[nMaxima]= f[maxLocs[jj]+peaksOffset];
				yMaxima[nMaxima] = tempYmax;
				nMaxima++;
			}
	  	}
	  	
		freqMain = xMaxima[0];
		perMain = 1/freqMain;
		amplMain = yMaxima[0];
		extraTxt = "";
		per2 = -1;
		ampl2 = -1;
			
		if (nMaxima>1) {
			per2 =  1/xMaxima[1];
			ampl2 = 2.8*yMaxima[1];
			extraTxt = " per2 " + 1/xMaxima[1] +  " Amp2 " + 2.8*yMaxima[1] + ""; 
		}
	}
		
	  if (doPlot == true) {
		Plot.create("Fourier amplitudes: "+windowType, "frequency (Hz)", "log(amplitude)", f, y);
		Plot.setLogScaleY(true);
		Array.getStatistics(y, min, max, mean, stdDev);
		yMin = pow(10,floor(log(min)/log(10)));
		yMax = pow(10,1+floor(log(max)/log(10)));
		Array.getStatistics(f, min, max, mean, stdDev);
		xMax = max;
		xMin = min;
        Plot.setLimits(xMin,xMax,yMin,yMax);
	  	Plot.setColor("red","red");
	  	Plot.setLineWidth(3);
		if (maxLocs.length != 0) Plot.add("circles",xMaxima,yMaxima);
		Plot.setColor("black");
		Plot.setLineWidth(1);
		Plot.setFontSize(16);
		if (maxLocs.length != 0) Plot.addText("Primary period "+ (1/freqMain) + " Amp " + amplMain*2.8 + " RMS " + rawRMS + " Range " + rawRange + extraTxt, 0.1, 1);
		if (maxLocs.length == 0) Plot.addText("no maxima found", 0.1, 1);
		Plot.show();
		}
	
	returnArray = newArray(nPeaks,tPk2PkMean, tPk2PkSD, pkHeightMean, pkHeightSD, baselineMean, baselineSD,fwhmMean, fwhmSD, decayConstMean, decayConstSD, gaussr2Mean, gaussr2SD,expr2Mean, expr2SD, preferredModelMean, perMain, amplMain,per2, ampl2,tPeak0,tPeak1);  
	returnArrayLabels = newArray("nPeaks","tPk2PkMean", "tPk2PkSD", "pkHeightMean", "pkHeightSD","baselineMean", "baselineSD","fwhmMean", "fwhmSD", "decayConstMean", "decayConstSD", "gaussr2Mean", "gaussr2SD","expr2Mmean", "expr2SD","preferredModelMean", "perMain", "amplMain","per2", "ampl2","tPeak0","tPeak1"); 
	return returnArray;
}

	function sort_B_by_sortedA(a,b) {quickSort(a, 0, lengthOf(a)-1,b);}
	
	function quickSort(a, from, to,b) {
	      i = from; j = to;
	      center = a[(from+to)/2];
	      do {
	          while (i<to && center>a[i]) i++;
	          while (j>from && center<a[j]) j--;
	          if (i<j) {
			temp=a[i]; 
			a[i]=a[j]; 
			a[j]=temp;
			tempc=b[i]; 
			b[i]=b[j]; 
			b[j]=tempc;
		}
	          if (i<=j) {i++; j--;}
	      } while(i<=j);
	      if (from<j) quickSort(a, from, j, b);
	      if (i<to) quickSort(a, i, to, b);
	}
	

