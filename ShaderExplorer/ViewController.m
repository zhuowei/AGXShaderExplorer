//
//  ViewController.m
//  ShaderExplorer
//
//  Created by Zhuowei Zhang on 2021-01-10.
//

#import "ViewController.h"
#import "AppDelegate.h"

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UILabel* urlLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    AppDelegate* appDelegate = (AppDelegate*)[UIApplication sharedApplication].delegate;
    self.urlLabel.text = appDelegate.serverUrl.description;
}

@end
