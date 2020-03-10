/*
 * assumes that an image is open and that the ROIset of interest is loaded into the ROI manager
 * 
 * future versions should test of X & Y are in results sheet an not delete of possible (i.e. add to measurements)
 */



nNN = 10;
nROIs = roiManager("Count");
img0 = getTitle();
run("Clear Results");
run("Set Measurements...", "mean centroid redirect=None decimal=3");
roiManager("Measure");
xList = newArray(nROIs);
yList = newArray(nROIs);
means = newArray(nROIs);
distances = newArray(nROIs);
ranks = newArray(nROIs);
nnArray = newArray(nNN);

for (i=0;i<nROIs;i++){
	xList[i] = getResult("X",i);
	yList[i] = getResult("Y",i);
	means[i] = getResult("Mean",i);
}

run("Clear Results");

for (j = 0;j<xList.length;j++) {
	distances = newArray(nROIs);
	for (k = 0;k<xList.length;k++) {
		//calculate distances between all pairs
		distances[k] = sqrt( pow(xList[j] - xList[k],2) + pow(yList[j] - yList[k],2));
		// find nNN closest k (=ROI number)
	}
		rankPosArr = Array.rankPositions(distances);
		ranks = Array.rankPositions(rankPosArr);
		// sort again to give a sorted list of the ROI number ranked wrt distance to reference ROI
		sortedNNIndex = Array.rankPositions(ranks);
		Array.print(distances);
		//Array.print(ranks);
		Array.print(sortedNNIndex);
		setResult("Label",j,img0);
		setResult("ROI",j,j+1);
		setResult("mean",j,means[j]);
		setResult("X",j,xList[j]);
		setResult("Y",j,yList[j]);
		for (i=1;i<=nNN;i++){
			setResult("NN"+i,j,sortedNNIndex[i]+1);
		}
		for (i=1;i<=nNN;i++){
			setResult("NN"+i+" dist",j,distances[sortedNNIndex[i]]);
		}
		for (i=1;i<=nNN;i++){
			residual = means[j]-means[sortedNNIndex[i]];
			print("residual = " + residual);
			setResult("NN"+i+" residual",j,residual);
		}
		

}
