//
//  LogViewController.m
//  Monal
//
//  Created by Anurodh Pokharel on 12/20/13.
//
//

#import "LogViewController.h"
#import "MonalAppDelegate.h"


@interface LogViewController ()

@end

@implementation LogViewController

DDFileLogger* _logger;
DDLogFileInfo* _logInfo;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

-(void) viewDidAppear:(BOOL)animated
{
    
    [super viewDidAppear:animated];
    MonalAppDelegate* appDelegate = (MonalAppDelegate*) [UIApplication sharedApplication].delegate;
    _logger = appDelegate.fileLogger;
    NSArray* sortedLogFileInfos = [_logger.logFileManager sortedLogFileInfos];
    _logInfo = [sortedLogFileInfos objectAtIndex: 0];

    [self reloadLog];
    
    [self scrollToBottom];
}

-(IBAction)shareAction:(id)sender
{
    NSArray* sharedText = [NSArray arrayWithObjects:[self.logView text],  nil];
    UIActivityViewController* shareController = [[UIActivityViewController alloc] initWithActivityItems:sharedText applicationActivities:nil];

    [self presentViewController:shareController animated:YES completion:^{}];
}

-(void) reloadLog {
    NSError* error;
    self.logView.text=[NSString stringWithContentsOfFile:_logInfo.filePath encoding:NSUTF8StringEncoding error:&error];
}

-(void) scrollToBottom {
    NSRange range = NSMakeRange(self.logView.text.length - 1, 1);
    [self.logView scrollRangeToVisible:range];
}

-(void) scrollToTop {
    NSRange range = NSMakeRange(0, 0);
    [self.logView scrollRangeToVisible:range];
}

/*
 * Toolbar button
 */

- (IBAction)rewindButton:(id)sender {
    [self scrollToTop];
}

- (IBAction)fastForwardButton:(id)sender {
    [self scrollToBottom];;
}

- (IBAction)refreshButton:(id)sender {
    [self reloadLog];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
