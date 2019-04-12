function [matchPositions, matchMetrics, template] = normxcorrDetector(parentImage,template,varargin)
% Detect subregion(s) using normalized cross-correlations; return
% position(s) of super-threshold match(es).
%
% [MATCHPOSITIONS, MATCHMETRICS] = NORMXCORRDETECTOR(PARENTIMAGE,...
%    TEMPLATE,...
%    PV_PAIRS);
%
%   (Supports any numeric data type, including logical. See normxcorr2.)
% 
% SYNTAX
%
% [matchPositions, matchMetrics, template] = normxcorrDetector(...
%    parentImage, template);
%
%       parentImage is the image to be searched;
% 
%       template indicates "subimage" that is to be detected. If empty, the
%       user is prompted to select a template interactively. 
%
% [...] = normxcorrDetector(..., 'matchThreshold', matchThreshold);
%    Optionally specify a scalar matchThreshold, indicating the minimum value
%    of normxcorr2 that constitutes a match. Reasonably, matchThreshold should
%    be on the interval [0.5, 1]. If empty, the single best match is
%    returned. (Default: 0.95).
%
% [...] = normxcorrDetector(..., 'showDetections', {true, false});
%    If true, visualize the positions of successful matches on the parent
%    image. (Default: true).
%
% [...] = normxcorrDetector(..., 'simplifyTemplate', {true, false});
%    If true, masks single (bright or dark) object in the center of the
%    template. Use with 'objectPolarity' to facilitate detection in
%    cluttered images. (See Example 4 below.) (Default: false).
%
% [...] = normxcorrDetector(..., 'objectPolarity', {'bright', 'dark'});
%    If 'simplifyTemplate' is true, indicates whether the object to be
%    detected is bright or dark. Otherwise, this parameter is ignored.
%    (Default: 'bright').
%
% [...] = normxcorrDetector(..., 'verbose', {true, false});
%    Indicates whether templates and surface plots of correlation values are
%    displayed. (Default: false.)
%
% OUTPUTS:
% matchPositions
%     A m x 4 array of bounding boxes of regions/items detected (at
%     specified matchThreshold), given as [x y width height];
%
% matchMetrics
%     A vector of m match metrics (normalized cross correlation values);
% 
% template
%     The image used as a template. (Useful if the template is created
%     interactively in a call to normxcorrDetector.)
%
% % EXAMPLES:
% 
% % Example 1: Specify parent and template images; find single-best match 
% %            (matchMetric = []); ('Verbose' is true):
%
% parentImage = imread('peppers.png');
% template = imread('onion.png');
% [matchPositions,matchMetrics] = normxcorrDetector(parentImage,template);
%
% % Example 2: Specify parent and matchThreshold; prompt for template:
% 
% parentImage = imread('eSFRTestImage.jpg');
% matchThreshold = 0.8 ;
% normxcorrDetector(parentImage,[],'matchThreshold',matchThreshold);
%
% % Example 3: Specify parent image; prompt for template:
%
% parentImage = imread('rice.png');
% matchThreshold = 0.8;
% [matchPositions,matchMetrics,template] = normxcorrDetector(parentImage,[],...
%    'matchThreshold',matchThreshold);
%
% % Example 4: Specify parent image and template. SIMPLIFY template
% %            by masking single bright object in it:
% 
% parentImage = imread('rice.png');
% pos = [222 37 31 19];
% template = imcrop(parentImage,pos);
% matchThreshold = 0.7; 
% simplifyTemplate = true;
% objectPolarity = 'bright';
% [matchPositions,matchMetrics,template] = normxcorrDetector(parentImage,template,...
%    'matchThreshold',matchThreshold,...
%    'simplifyTemplate',simplifyTemplate,...
%    'objectPolarity',objectPolarity);
%
%
% NOTE: Adapted from "Registering an Image Using Normalized Cross Correlation" doc example.
%
% Brett Shoelson, PhD
% brett.shoelson@mathworks.com
% 04/01/2018; 4/12/2019 (minor improvements, changes to defaults.)
%
% See Also: normxcorr2 SURFDetector

% Copyright 2019 The MathWorks, Inc.

% Parse:
[matchThreshold,objectPolarity,showDetections,simplifyTemplate,verbose] = ...
    parseInputs(varargin{:});
%
%togglefig('Parent Image')
%imshow(parentImage)
%t = title('Parent');

origParentImage = parentImage;
if isempty(template)
    togglefig('Parent Image')
    imshow(origParentImage);
    t = title('');
    t.String = 'Drag to Select Template (Dbl-Click to Finish)';
    t.Color = 'r';
    h = imrect; %#ok<IMRECT>
    wait(h);
    t.String = 'Parent';
    t.Color = 'k';
    template = imcrop(parentImage,h.getPosition);
    delete(h);
end

% normxcorr2 supports grayscale:
if size(parentImage,3) ~= 1
    parentImage = rgb2gray(parentImage);
end

originalTemplate = template;
if size(template,3) ~= 1
    template = rgb2gray(template);
end

if simplifyTemplate
    switch objectPolarity
        case 'bright'
            mask = im2single(template) > graythresh(template);
        case 'dark'
            mask = im2single(template) < graythresh(template);
        otherwise
            error('normxcorrDetector: Unrecognized ''objectPolarity'' value.')
    end
    originalTemplate = template;
    mask = bwareafilt(mask,1);
    bgVal = median(template(~mask));
    template(~mask) = bgVal;
    if verbose
        togglefig('Template/Masked Template')
        subplot(1,2,1)
        imshow(originalTemplate);
        title('Original template')
        subplot(1,2,2);
        imshow(template)
        title('Masked Template')
    end
end
tic;
if verbose
    togglefig('Template')
    imshow(originalTemplate)
end

% Compute Normalized Cross-Correlation
% Calculate the normalized cross-correlation and display it as a surface
% plot. The peak of the cross-correlation matrix occurs where the
% sub_images are best correlated. normxcorr2 only works on grayscale
% images, so we pass it the red plane of each sub image.
c = normxcorr2(template(:,:,1),parentImage(:,:,1));
absC = abs(c);
if verbose
    togglefig('NormXcorr2')
    surf(c)
    shading flat
end

% Replace peaks with regional maxima to avoid duplicate detections:
absC = c .* imregionalmax(absC);

%  Find Coordinates and Offsets of Peak(s)
if isempty(matchThreshold)
    [matchMetrics, matches] = max(absC(:));
else
    matches = find(absC(:) >= matchThreshold);
    % Initialize:
    matchMetrics = zeros(numel(matches),1);
end

matchPositions = nan(numel(matches),4);
for ii = 1:numel(matches)
    matchMetrics(ii) = absC(matches(ii));
    [ypeak, xpeak] = ind2sub(size(c),matches(ii));
    offset = [(xpeak-size(template,2))
        (ypeak-size(template,1))];
    xoffset = offset(1);
    yoffset = offset(2);
    
    % Determine where template falls inside of parentImage.
    xbegin = round(xoffset+1);
    xend   = round(xoffset+ size(template,2));
    ybegin = round(yoffset+1);
    yend   = round(yoffset+size(template,1));
    matchPositions(ii,:) = [xbegin ybegin xend-xbegin yend-ybegin];
end %for loop
tDetect = toc;
fprintf('Detection time: %0.2f\n',tDetect);
if showDetections
    togglefig('Parent Image');
    imshow(origParentImage)
    for ii = 1:numel(matches)
        rectangle('Position',matchPositions(ii,:),...
            'EdgeColor','g','LineWidth',2);
        rectangle('Position',matchPositions(ii,:),...[xbegin ybegin xend-xbegin yend-ybegin],...
            'EdgeColor','k','LineWidth',2,'LineStyle','--');
        text(matchPositions(ii,1),matchPositions(ii,2),num2str(matchMetrics(ii),2),...
            'BackgroundColor','y',...
            'FontSize',7);
    end
end
end %main function call

function [matchThreshold,objectPolarity,showDetections,...
    simplifyTemplate,verbose] = parseInputs(varargin)
% Setup parser with defaults
parser = inputParser;
parser.CaseSensitive = false;
parser.addParameter('matchThreshold', 0.95);
parser.addParameter('objectPolarity', 'bright');
parser.addParameter('showDetections', true);
parser.addParameter('simplifyTemplate', false);
parser.addParameter('verbose',false);
% Parse input
parser.parse(varargin{:});
% Assign outputs
r = parser.Results;
[matchThreshold,objectPolarity,showDetections,simplifyTemplate,verbose] = ...
    deal(r.matchThreshold,r.objectPolarity,r.showDetections,...
    r.simplifyTemplate,r.verbose);
end %parseInputs
