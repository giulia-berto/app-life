function s_ms_mt_fornix_pooledsd(hemisphere,saveDir)
%
% This script performs a test of conenctivity of MT+ (LO1 and LO2) with
% the anterior commissure (FRNX).
%
% The following are the steps we perform:
%  - It loads a culled half hemisphere connectome (FE structure). 
%  - It loads the MT+ ROI.
%  - It loads the FORNIX ROI (a 4mm sphere). 
%  - It finds the fascicles connecting MT+ and fornix
%  - It reduces the connectome to the voxels and fibers of the conenctions
%  - It Perform a bootstrap test WITH and WITHOUT the connection between
%    MT+ and fornix.
%
%
% Copyright Franco Pestilli (2013) Vistasoft Stanford University.

% Handle parallel computing
if matlabpool('size') == 0
    c = parcluster;
    c.NumWorkers = 12;
    matlabpool(c);
end

if notDefined('saveDir'),
    saveDir = sprintf('~/Dropbox/connectomes_plot_mt_frnx/%s',mfilename);
end
if notDefined('hemisphere'), hemisphere = {'left','right'};end
if notDefined('plotSlices'), plotSlices = 0;end

nboots      = 10000;
nmontecarlo = 20;

for ih = 1:length(hemisphere)
    % Set all the variables that depend on the hemisphere
    switch hemisphere{ih}
        case {'left'}
            feFileName = 'fe_culled_FP_150_B2000_LMAX8_left.mat';
            fgName     = 'FP_LH_150_B2000_LMAX8.mat';
            frnxRoi    = 'fornix_sphere_4mm.mat';
            mtRoi      = 'LTO1_O2_cleaned.mat';
            notRoi     = 'FP_LH_NOT_fornix_test';
            ccRoi      = 'FP_CC_NOT_fornix_test';
            axisLims   = [-55 5 -80 40];
            vw         = [-75,0];
            slices     = {[-1 0 0],[0 -40 0],[0 0 -14 ]};
            lght       = 'left';
            SLaxLims   = [-55 2 -120 120 -20 40 ];
            histcolor{1}  = [0.4 0.4 0.4];
            histcolor{2}  = [.6 0.4 0.4];
            
        case {'right'}
            feFileName = 'fe_culled_FP_150_B2000_LMAX8_right.mat';
            fgName     = 'FP_RH_150_B2000_LMAX8.mat';
            frnxRoi     = 'fornix_sphere_4mm.mat';
            mtRoi      = 'RTO1_O2_cleaned.mat';
            notRoi     = 'FP_RH_NOT_fornix_test';
            ccRoi      = 'FP_CC_NOT_fornix_test';axisLims   = [-5 55 -80 40];
            vw         = [75,30];
            slices     = {[18 0 0],[0 -40 0],[0 0 -14 ]};
            lght       = 'right';
            SLaxLims   = [-2 55 -120 120 -20 40 ];
            histcolor{1}  = [0 0 0];
            histcolor{2}  = [.8 0.4 0.4];
            
        otherwise
            keyboard
    end
    
    % Load the FE structure
    feDir      = '/azure/scr1/frk/150dirs_b1000_b2000_b4000/results/life_mrtrix_rep1/fe_hemispheres';
    roiDir = '/azure/scr1/frk/150dirs_b1000_b2000_b4000/results/life_mrtrix_rep1/mt_roi';
    %t1File = '/azure/scr1/frk/150dirs_b1000_b2000_b4000/150dirs_b2000/t1/t1.nii.gz';
    fgDir = '/azure/scr1/frk/150dirs_b1000_b2000_b4000/life_mrtrix_rep1';
    
    if ~(exist([fullfile(feDir,feFileName),'.mat'],'file') == 2)
        % Load the ROIs
        disp('Loading ROIs...')
        mtFileName   = fullfile(roiDir,mtRoi);
        frnxFileName = fullfile(roiDir,frnxRoi);
        notFileName  = fullfile(roiDir,notRoi);
        ccFileName   = fullfile(roiDir,ccRoi);
        mt           = dtiReadRoi(mtFileName);
        frnx         = dtiReadRoi(frnxFileName);
        notH         = dtiReadRoi(notFileName);
        CC           = dtiReadRoi(ccFileName);
        
        disp('Loading the whole-hemisphere fiber group...')
        % Load the unculled hemisphere connectome to get the connection
        fg         = fgRead(fullfile(fgDir,fgName));
        
        % Find the fascicles in the Fiber group of the hemisphere that touch both MT+ and FRNX.
        disp('Finding the tract connecting MT and the fornix...')
        operations = {'and','and','not','not'};
        rois       = {mt,frnx,notH,CC};
        [mtFrnxFG, keepFascicles] = feSegmentFascicleFromConnectome(fg, rois, operations, 'mt_frnx_zero');
        
        % Extract the FG from the culled connectome.
        disp('Loading the FE structure for the culled connectome in the hemisphere...')
        load(fullfile(feDir,feFileName));
        fg            = feGet(fe,'fibers acpc');
        dwiFile       = '/biac2/wandell2/data/diffusion/pestilli/20110922_1125/raw/0005_01_DTI_2mm_150dir_2x_b2000_aligned_trilin.nii.gz';
        dtFile        = feGet(fe,'dt file');
        fgFileName    = [fgName(1:end-4),'_culled_plus_fornix'];
        feFileName    = [feGet(fe,'name'),'_plus_fornix'];
        feSavedir     = feDir;
        dwiFileRepeat =  '/biac2/wandell2/data/diffusion/pestilli/20110922_1125/raw/0007_01_DTI_2mm_150dir_2x_b2000_aligned_trilin.nii.gz';
        t1File        = feGet(fe,'anatomy file');
        clear fe % Clear the stucture we will rebuild it
        
        % Add the fornix tract to the culled fiber group. Remember this tract was
        % originally deleted during culling. We put it back now, fit the connectome
        % and test the evidence in favor for it.
        disp('Adding the fibers between MT and fornix to the culled connectome...')
        numOrigFibers = length(fg.fibers);
        numFrnxFibers = length(mtFrnxFG.fibers);
        fgMT_FRNX     = fgMerge(fg,mtFrnxFG,fgFileName); % The new fibers will be the last ones
        
        % Rebuild the model.
        fe = feConnectomeInit(dwiFile,dtFile,fgMT_FRNX,feFileName,feSavedir,dwiFileRepeat,t1File);
        
        % Fit or cull the model.
        fefit     = feFitModel(feGet(fe,'Mfiber'),feGet(fe,'dsigdemeaned'),'sgdnn');
        fe        = feSet(fe,'fit', fefit);
        fprintf('[%s] saving FE structure: \n%s ...\n',mfilename,fullfile(feGet(fe,'savedir'),feGet(fe,'name')))
        save(fullfile(feGet(fe,'savedir'),feGet(fe,'name')),'fe','-v7.3')
    else
        fprintf('[%s] loading FE structure: \n%s.mat ...\n',mfilename,fullfile(feGet(fe,'savedir'),feGet(fe,'name')))
        load([fullfile(feGet(fe,'savedir'),feGet(fe,'name')),'.mat'],'fe')
    end
    
    % Find the fascicles in the connectome that touch both MT+ and FRNX.
    fg         = feGet(fe,'fibers acpc');
    [mtFrnxFG, keepFascicles] = feSegmentFascicleFromConnectome(fg, rois, operations, 'mt_frnx_zero');
    
    % % Show te new fiber group
    % % High-resolution Anatomy
    % t1       = niftiRead(t1File);
    % figName = sprintf('Test_MT_FRNX_connection_brain_%s_%s',hemisphere{ih},feFileName(1:end-4));
    % figureHandle = mrvNewGraphWin(figName);
    % h  = mbaDisplayBrainSlice(t1, slices{1});
    % hold on
    % %h  = mbaDisplayBrainSlice(t1, slices{2});
    % h  = mbaDisplayBrainSlice(t1, slices{3});
    % trfrnxtColor = [.8 .6 .2];%[.3 .7 .9];
    % [figureHandle, lightHandle, sHandle] = mbaDisplayConnectome(mtFrnxFG.fibers,figureHandle,trfrnxtColor,'uniform');
    % delete(lightHandle)
    % view(vw(1),vw(2));
    % axis(axisLims);
    % lightHandle = camlight(lght);
    % set(gcf,'Position',[0.0148 0.0148 .35 .87])
    % drawnow
    % saveFig(figureHandle,fullfile(saveDir,figName),'jpg')
    
    % Reduce the connectome to the voxels and fibers of the connection between
    % MT+ and FRNX.
    [feWithoutFas, feWithFas, ~] = feTestFascicle(fe,keepFascicles,0);
    
    if plotSlices
        slice  = {[0 -56 0],[0 -58 0],[0 -60 0],[0 -62 0],[0 -64 0],[0 -66 0], ...
            [0 -68 0],[0 -70 0],[0 -72 0],[0 -74 0]};
        t1     = niftiRead(t1File);
        
        for iS = 1:length(slice)
            % Make a figure of brain slice of the RMSE with the fascicle
            figName = sprintf('rmse_map_WITH_%s_slice%i_%s',feFileName(1:end-4),slice{iS}(find(slice{iS})),hemisphere{ih});
            shW = makeBrainMap(feWithFas,t1,slice{iS},SLaxLims,figName,saveDir);
            
            % Make a figure of brain slice of the RMSE without the fascicle
            figName = sprintf('rmse_map_WITHOUT_%s_slice%i_%s',feFileName(1:end-4),slice{iS}(find(slice{iS})),hemisphere{ih});
            shWO = makeBrainMap(feWithoutFas,t1,slice{iS},SLaxLims,figName,saveDir);
        end
    end
    
    % Make a plot of the R-squared
    WITH.rmse      = mean(feGetRep(feWithFas,   'vox  rmse'));
    WITH.rrmse     = median(feGetRep(feWithFas,   'vox  rmse ratio'));
    WITH.rmseall   = (feGetRep(feWithFas,   'vox  rmse'));
    
    WITHOUT.rmse    = median(feGetRep(feWithoutFas,'vox  rmse'));
    WITHOUT.rrmse   = median(feGetRep(feWithoutFas,'vox  rmse ratio'));
    WITHOUT.rmseall = (feGetRep(feWithoutFas,'vox  rmse'));
    
    %% The following is the code for the bootstrap test on the MEAN rmse
    sizeWith    = length(WITH.rmseall);
    nullDistributionW = nan(nboots,nmontecarlo);
    nullDistributionWO = nan(nboots,nmontecarlo);
    clear y x y_m y_e ;
    disp('Peforming bootstrap...')
    for inm = 1:nmontecarlo
        parfor ibt = 1:nboots
            nullDistributionW(ibt,inm) = mean(randsample(WITH.rmseall,   sizeWith,true));
            nullDistributionWO(ibt,inm) = mean(randsample(WITHOUT.rmseall,sizeWith,true));
        end
        
        % Distribution With
        [y(:,inm),xhis] = hist(nullDistributionW(:,inm),linspace(26.5,32,200));
        y(:,inm) = y(:,inm)./sum(y(:,inm));
        
        % Distribution without
        [woy(:,inm),woxhis] = hist(nullDistributionWO(:,inm),linspace(26.5,32,200));
        woy(:,inm) = woy(:,inm)./sum(woy(:,inm));
    end
    y_m = mean(y,2);
    y_e = [y_m, y_m] + 2*[-std(y,[],2),std(y,[],2)];
    
    ywo_m = mean(woy,2);
    ywo_e = [ywo_m, ywo_m] + 2*[-std(woy,[],2),std(woy,[],2)];
    
    % Plot the null distribution and the empirical difference
    figName = sprintf('Test_MT_FRNX_connection_rmse_mean_HIST_%s_%s',hemisphere{ih},feFileName(1:end-4));
    fh = mrvNewGraphWin(figName);
    %bar(x,y_m,'k')
    %plot([xhis,xhis],y_e','color',[.3 .3 .3]); % Error bars for the distribution in
    patch([xhis,xhis],y_e(:),histcolor{1},'FaceColor',histcolor{1},'EdgeColor',histcolor{1}); % Distribution as the +/- 2SD
    hold on
    patch([woxhis,woxhis],ywo_e(:),histcolor{2},'FaceColor',histcolor{2},'EdgeColor',histcolor{2}); % Distribution as the +/- 2SD
    set(gca,'tickdir','out', ...
        'box','off', ...
        'ylim',[0 0.1], ...
        'xlim',[27,31], ...
        'ytick',[0 0.05 0.1], ...
        'xtick',[26 28 30 32], ...
        'fontsize',16)
    ylabel('Probability','fontsize',16)
    xlabel('rmse','fontsize',16')
    
    % (3) Compute the probability that the empirical difference (1) was
    %     observed by chance given th data, by looking at the percentile of the
    %     empirical difference in the Nul distribution (2).
    dprime_mean(:,ih) = diff([mean(nullDistributionW,1);mean(nullDistributionWO,1)])./sqrt(sum([std(nullDistributionW,[],1);std(nullDistributionWO,[],1)].^2,1));
    title(sprintf('Strength of connection evidence %2.3f',mean(dprime_mean(:,ih))), ...
        'FontSize',16)
    saveFig(fh,fullfile(saveDir,figName),'eps')
    
    %% The following is the code for the bootstrap test of the difference in rmse
    %
    % Compute a test of the diference in rmse
    % (1) Get the differece in rmse observed empiriclly
    EmpiricalDiff = WITHOUT.rmse(1) - WITH.rmse(1);
    
    % (2) Compute the Null distribution by:
    % (2.1) Combine all the rmse from both WITH and WITHOUT.
    % (2.2) Compute 10,000 distributions of rmse one for WITH one for WITHOUT
    %       with the same numerosity of the initial samples
    % (2.3) Compute the difference between the medians of these 10,000
    %       distributions.
    NullSet     = [WITHOUT.rmseall WITH.rmseall];
    sizeWith    = length(WITH.rmseall);
    sizeWithout = length(WITHOUT.rmseall);
    
    clear y x y_m y_e ;
    
    nullDistribution = nan(nboots,nmontecarlo);
    for inm = 1:nmontecarlo
        parfor ibt = 1:nboots
            % Y = RANDSAMPLE(POPULATION,K)
            BootWith    = mean(randsample(NullSet,sizeWith,true));
            BootWithout = mean(randsample(NullSet,sizeWithout,true));
            nullDistribution(ibt,inm) = BootWithout - BootWith;
        end
        
        [y(:,inm),xhis] = hist(nullDistribution(:,inm),linspace(-3,3,100));
        y(:,inm) = y(:,inm)./sum(y(:,inm));
    end
    y_m = mean(y,2);
    y_e = [y_m, y_m] + 2*[-std(y,[],2),std(y,[],2)];
    
    % Plot the null distribution and the empirical difference
    figName = sprintf('Test_MT_FRNX_connection_rmseDiff_HIST_%s_%s',hemisphere{ih},feFileName(1:end-4));
    fh = mrvNewGraphWin(figName);
    %bar(x,y_m,'k')
    %plot([xhis,xhis],y_e','color',[.3 .3 .3]); % Error bars for the distribution in
    patch([min(xhis), xhis,xhis, max(xhis)],[0, y_e(:)', 0],histcolor{1},'FaceColor',histcolor{1},'EdgeColor',histcolor{1}); % Distribution as the +/- 2SD
    hold on
    plot([EmpiricalDiff,EmpiricalDiff],[0 max(y_m)],'r-','linewidth',2)
    axis([-2 2 0 0.1])
    set(gca,'tickdir','out', ...
        'box','off', ...
        'ylim',[0 0.1], ...
        'xlim',[-3.5 3.5], ...
        'ytick',[0 0.05 0.1], ...
        'xtick',[-3 -1.5 0 1.5 3], ...
        'fontsize',16)
    ylabel('Probability','fontsize',16)
    xlabel('Difference in rmse','fontsize',16')
    
    % (3) Compute the probability that the empirical difference (1) was
    %     observed by chance given th data, by looking at the percentile of the
    %     empirical difference in the Nul distribution (2).
    nullD = mean(nullDistribution,2);
    nullY = mean(y,2);
    if max(nullD)<EmpiricalDiff
        p = 100*1/nboots;
    else  p = 1 - sum(nullY( xhis > EmpiricalDiff ));
    end
    dprime_d(:,ih) = EmpiricalDiff/std(nullD);
    title(sprintf('The probability of obtaining the difference by chance is less than %2.6f%%\nStrength of connection evidence %2.3f',p,mean(dprime_d(:,ih))), ...
        'FontSize',16)
    saveFig(fh,fullfile(saveDir,figName),'eps')
    
    % Make a scatter plot:
    figName = sprintf('Test_MT_FRNX_connection_rmse_SCATTER_%s_%s',hemisphere{ih},feFileName(1:end-4));
    fh = mrvNewGraphWin(figName);
    hold on
    plot([0 80],[0 80],'k-',[median(WITH.rmse),median(WITH.rmse)],[0 80],'k--',[0 80],[median(WITHOUT.rmse),median(WITHOUT.rmse)],'k--')
    plot(WITH.rmseall,WITHOUT.rmseall,'o','color',[.35 .35 .95],'markerFaceColor',[.35 .35 .95],'MarkerSize',12);
    axis square
    set(gca,'tickdir','out','box','off', ...
        'xlim',[0 80], ...
        'ylim',[0 80], ...
        'ytick',[0 40 80], ...
        'xtick',[0 40 80], ...
        'ticklen',[0.025 0.05],'FontSize',16)
    xlabel('rmse WITH Trfrnxt','fontsize',16)
    ylabel('rmse WITHOUT Trfrnxt','fontsize',16)
    saveFig(fh,fullfile(saveDir,figName),'eps')
    
    figName = sprintf('Test_MT_FRNX_connection_rmse_MAP_%s_%s',hemisphere{ih},feFileName(1:end-4));
    fh = mrvNewGraphWin(figName);
    [ymap,x]= hist3([WITHOUT.rmseall;WITH.rmseall]',{[0:2:60], [0:2:60]});
    ymap = ymap./length(WITHOUT.rmseall);
    sh = imagesc(flipud(log10(ymap)));
    cm = colormap(flipud(hot));
    axis('square')
    set(gca,'xlim',[0 length(x{2})+1],...
        'ylim',    [0 length(x{2})+1], ...
        'ytick',[0 (length(x{2})+1)/2 length(x{2})+1], ...
        'xtick',[0 (length(x{2})+1)/2 length(x{2})+1], ...
        'yticklabel',[x{2}(end) x{2}(round(end/2)) 0], ...
        'xticklabel',[0 x{2}(round(end/2)) x{2}(end)], ...
        'tickdir','out','box','off', ...
        'fontsize',16,'visible','off');
    saveFig(fh,fullfile(saveDir,figName),'jpg')
    hold on
    plot([1 length(x{2})],[length(x{2}) 1],'k-');
    cb = colorbar;
    tck = get(cb,'ytick');
    set(cb,'yTick',[min(tck)  mean(tck) max(tck)], ...
        'yTickLabel',round(1000*10.^[min(tck),...
        mean(tck), ...
        max(tck)])/1000, ...
        'tickdir','out','ticklen',[.025 .05],'box','on', ...
        'fontsize',16','visible','on')
    set(gca,'visible','on')
    saveFig(fh,fullfile(saveDir,figName),'eps')

% Make a plot fo the strenght fo conenction evidnce:
figName = sprintf('Test_MT_FRNX_S_difference_RMSE_bar_%s_%s',hemisphere{ih},feFileName(1:end-4));
fh = mrvNewGraphWin(figName);
mStrength = mean(dprime_d,1);
eStrength = [mStrength;mStrength] + 2*[-std(dprime_d,[],1);std(dprime_d,[],1)];
hb = bar(mStrength,'facecolor','k');
hold on
plot([1 1; 2 2]',[eStrength],'r-','linewidth',4)
set(gca,'xlim',[0.5 1.5],...
    'ylim',    [0 4], ...
    'ytick',[0 2 4], ...
    'xtick',[1], ...
    'xticklabel',{hemisphere{1}, hemisphere{2}}, ...
    'tickdir','out','box','off', ...
    'fontsize',16,'visible','on');
ylabel(sprintf('S'),'FontSize',16)
saveFig(fh,fullfile(saveDir,figName),'eps')

% Make a plot fo the strenght fo conenction evidnce:
figName = sprintf('Test_MT_FRNX_S_mean_RMSE_bar_%s_%s',hemisphere{ih},feFileName(1:end-4));
fh = mrvNewGraphWin(figName);
mStrength = mean(dprime_mean,1);
eStrength = [mStrength;mStrength] + 2*[-std(dprime_mean,[],1);std(dprime_mean,[],1)];
hb = bar(mStrength,'facecolor','k');
hold on
plot([1 1; 2 2]',[eStrength],'r-','linewidth',4)
set(gca,'xlim',[0.5 1.5],...
    'ylim',    [0 4], ...
    'ytick',[0 2 4], ...
     'xtick',[1], ...
    'xticklabel',{hemisphere{1},hemisphere{2}}, ...
    'tickdir','out','box','off', ...
    'fontsize',16,'visible','on');
ylabel(sprintf('S'),'FontSize',16)
saveFig(fh,fullfile(saveDir,figName),'eps')
end % Hemisphere

end % Main function

%%%%%%%%%%%%%%%%%%%%%%%
function [fh,sh] = makeBrainMap(fe,t1,slice,axLims,figName,saveDir)

% Make a map of the RMSE WITH and WITHOUT the fascicle:
coords  = feGet(fe,'roi coords') + 1;
xform   = feGet(fe,'xform img 2 frnxpc');
         
% Cross-validate RMSE
rmse = feGetRep(fe, 'vox rmse');
img  = feReplfrnxeImageValues(nan(feGet(fe,'map size')),rmse,coords);
maxr = 50;

% Make anifti file from the rmse
ni  = niftiCreate('data',mbaNormalize(img,[0,1]), ...
    'qto_xyz',xform, ...
    'fname','rmse', ...
    'data_type',class(img));

% Open a figure
fh = mrvNewGraphWin(figName);

% Show the anatomy with the overlay
sh = mbaDisplayOverlay(t1, ni, slice, [], 'hot');

axis(axLims)

saveMap(fh,figName,saveDir,nanmean(img(:)),nanmedian(img(:)),nanstd(img(:)),maxr)
end

%---------------------------------%
function saveMap(fh,figName,saveDir,M,m,SD,maxfd)
% This helper function saves two figures for efrnxh map and eps with onlythe
% axis and a jpg with only the brain slice.
% The two can then be combined in illustrator.
%
% First we save only the slice as jpeg.
set(gca,'fontsize',16,'ztick',[-20 0 20 40], ...
    'xtick',[-50 -25 0 25 50], ...
    'tickdir','out','ticklength',[0.025 0])
axis off
saveFig(fh,fullfile(saveDir,'maps',figName),'tiff')
saveFig(fh,fullfile(saveDir,'maps',figName),'png')

% Then we save the slice with the axis as
% eps. This will only generate the axis
% that can be then combined in illustrator.
axis on
grid off

title(sprintf('mean %2.2f | median %2.2f | SD %2.2f', ...
    M,m,SD),'fontsize',16)
zlabel('Z (mm)','fontsize',16)
xlabel('X (mm)','fontsize',16)
cmap = colormap(hot(255));
colorbar('ytick',linspace(0,1,5),'yticklabel', ...    
    {linspace(0,1,5)*50}, ...
    'tickdir','out','ticklength',[0.025 0],'fontsize',16)
saveFig(fh,fullfile(saveDir,'maps',figName),1)
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function saveFig(h,figName,type)

% MAke sure the folder to save the figure exists
[p,f,e] = fileparts(figName);
[success,message] = mkdir(p);
if ~isempty(message), disp(sprintf('%s.',message));end

% Find out which type of figure and geenerate the proper printing command.
switch type
    case {0,'jpeg','jpg'}
        printCommand = (sprintf('print(%s, ''-djpeg90'',''-r500'' , ''-noui'', ''-opengl'', ''%s'')', num2str(h),figName));
    case {1,'eps'}
        printCommand = (sprintf('print(%s, ''-cmyk'', ''-depsc2'',''-tiff'',''-r500'' , ''-noui'', ''%s'')', num2str(h),figName));
    case 'png'
        printCommand =  (sprintf('print(%s, ''-dpng'',''-r500'', ''%s'')', num2str(h),figName));
    case 'tiff'
        printCommand = (sprintf('print(%s, ''-dtiff'',''-r500'', ''%s'')', num2str(h),figName));
    case 'bmp'
        printCommand = (sprintf('print(%s, ''-dbmp256'',''-r500'', ''%s'')', num2str(h),figName));
    otherwise
        keyboard
end

% do the printing here:
fprintf('[%s] saving figure... \n%s\n',mfilename,figName);
eval(printCommand);
end