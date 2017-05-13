//
// Copyright (c) 2016 Related Code - http://relatedcode.com
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "PictureView.h"
#define		SCREEN_WIDTH						[UIScreen mainScreen].bounds.size.width
#define		SCREEN_HEIGHT						[UIScreen mainScreen].bounds.size.height
//-------------------------------------------------------------------------------------------------------------------------------------------------
@interface PictureView()
{
	UIImage *picture;
	BOOL statusBarIsHidden;
}

@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) IBOutlet UIButton *buttonDone;
@property (strong, nonatomic) IBOutlet UIScrollView *scrollView;
@property BOOL zoomed;

@end
//-------------------------------------------------------------------------------------------------------------------------------------------------

@implementation PictureView

@synthesize imageView, buttonDone, scrollView;

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (id)initWith:(UIImage *)picture_
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	self = [super init];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	picture = picture_;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	return self;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewDidLoad
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewDidLoad];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(handleGesture:)];
    
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    tapGesture.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:tapGesture];
    
	[self.view addGestureRecognizer:panGestureRecognizer];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	statusBarIsHidden = [UIApplication sharedApplication].isStatusBarHidden;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	imageView.image = picture;
    scrollView.minimumZoomScale = 1.0;
    scrollView.maximumZoomScale = 2.0;
    scrollView.autoresizesSubviews = YES;
    //self.scrollView.contentSize = self.imageView.frame.size;
//self.scrollView.
    scrollView.delegate = self;
    

}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewDidAppear:animated];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	statusBarIsHidden = YES;
	[self setNeedsStatusBarAppearanceUpdate];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)viewDidLayoutSubviews
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[super viewDidLayoutSubviews];
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[self updatePictureDetails];
	[self updateHideDetails];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (BOOL)prefersStatusBarHidden
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return statusBarIsHidden;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (UIStatusBarStyle)preferredStatusBarStyle
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	return UIStatusBarStyleLightContent;
}

#pragma mark - UIPanGestureRecognizer methods


- (void)handleTapGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    if(self.zoomed)
        [self.scrollView setZoomScale:scrollView.minimumZoomScale animated:YES];
    else{
        CGRect zoomRect = [self zoomRectForScale:scrollView.maximumZoomScale
                                      withCenter:[gestureRecognizer locationInView:gestureRecognizer.view]];
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)handleGesture:(UIPanGestureRecognizer *)gestureRecognizer
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	CGFloat moveY = [gestureRecognizer translationInView:self.view].y;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	switch (gestureRecognizer.state)
	{
		case UIGestureRecognizerStateChanged:
		{
			self.imageView.center = CGPointMake(self.view.center.x, self.view.center.y + moveY);
			break;
		}
		case UIGestureRecognizerStateEnded:
		{
			[self gestureEnded:moveY];
			break;
		}
		case UIGestureRecognizerStateBegan:
		case UIGestureRecognizerStatePossible:
		case UIGestureRecognizerStateCancelled:
		case UIGestureRecognizerStateFailed:
			break;
	}
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)gestureEnded:(CGFloat)moveY
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	if (fabs(moveY) < 80)
	{
		[UIView animateWithDuration:0.3 animations:^{
			self.imageView.center = self.view.center;
		}];
	}
	else [self actionDismiss:moveY];
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)actionDismiss:(CGFloat)moveY
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	moveY = 600 * (moveY / fabs(moveY));
	//---------------------------------------------------------------------------------------------------------------------------------------------
	[UIView animateWithDuration:0.3 animations:^{
		self.imageView.center = CGPointMake(self.imageView.center.x, self.imageView.center.y + moveY);
	} completion:^(BOOL complete) {
		imageView.hidden = YES;
		[self dismissViewControllerAnimated:NO completion:nil];
	}];
}

#pragma mark - User actions

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (IBAction)actionDone:(id)sender
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	[self dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.imageView;
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale
{
    self.zoomed = (scale != 1);
}


#pragma mark - Helper methods

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)updatePictureDetails
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	CGFloat xpos, ypos, width, height;
	//---------------------------------------------------------------------------------------------------------------------------------------------
	if ((picture.size.width / picture.size.height) > (SCREEN_WIDTH / SCREEN_HEIGHT))
	{
		width = SCREEN_WIDTH;
		height = picture.size.height * width / picture.size.width;
		xpos = 0; ypos = (SCREEN_HEIGHT - height) / 2;
	}
	else
	{
		height = SCREEN_HEIGHT;
		width = picture.size.width * height / picture.size.height;
		ypos = 0; xpos = (SCREEN_WIDTH - width) / 2;
	}
	//---------------------------------------------------------------------------------------------------------------------------------------------
	imageView.frame = CGRectMake(xpos, ypos, width, height);
    self.scrollView.contentSize = self.imageView.frame.size;
}

//-------------------------------------------------------------------------------------------------------------------------------------------------
- (void)updateHideDetails
//-------------------------------------------------------------------------------------------------------------------------------------------------
{
	BOOL landscape = UIDeviceOrientationIsLandscape([UIDevice currentDevice].orientation);
	//---------------------------------------------------------------------------------------------------------------------------------------------
	buttonDone.hidden = landscape;
}

#pragma mark - zoom utilities
         
         - (CGRect)zoomRectForScale:(float)scale withCenter:(CGPoint)center {
             
             CGRect zoomRect;
             
             zoomRect.size.height = [self.imageView frame].size.height / scale;
             zoomRect.size.width  = [self.imageView frame].size.width  / scale;
             
             center = [self.imageView convertPoint:center fromView:self.view];
             
             zoomRect.origin.x    = center.x - ((zoomRect.size.width / 2.0));
             zoomRect.origin.y    = center.y - ((zoomRect.size.height / 2.0));
             
             return zoomRect;
         }
         
@end
