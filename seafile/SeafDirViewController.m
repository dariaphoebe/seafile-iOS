//
//  SeafUploadDirVontrollerViewController.m
//  seafile
//
//  Created by Wang Wei on 10/20/12.
//  Copyright (c) 2012 Seafile Ltd. All rights reserved.
//
#import "UIScrollView+SVPullToRefresh.h"

#import "SeafDirViewController.h"
#import "SeafAppDelegate.h"
#import "SeafDir.h"
#import "SeafRepos.h"
#import "SeafCell.h"
#import "Debug.h"
#import "UIViewController+Extend.h"
#import "SVProgressHUD.h"

@interface SeafDirViewController ()<SeafDentryDelegate>
@property (strong) SeafDir *curDir;
@property (strong) UIBarButtonItem *chooseItem;
@property (strong, readonly) SeafDir *directory;
@property (strong) id<SeafDirDelegate> delegate;
@property (readwrite) BOOL chooseRepo;

@end

@implementation SeafDirViewController

- (id)initWithSeafDir:(SeafDir *)dir delegate:(id<SeafDirDelegate>)delegate chooseRepo:(BOOL)chooseRepo
{
    if (self = [super init]) {
        self.delegate = delegate;
        _directory = dir;
        _directory.delegate = self;
        [_directory loadContent:NO];
        self.tableView.delegate = self;
        _chooseRepo = chooseRepo;
        if (_chooseRepo)
            [self.navigationController setToolbarHidden:YES];
    }
    return self;
}

- (void)cancel:(id)sender
{
    [self.delegate cancelChoose:self];
}

- (IBAction)chooseFolder:(id)sender
{
    [self.delegate chooseDir:self dir:_directory];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 50.0;
    [self.tableView registerNib:[UINib nibWithNibName:@"SeafDirCell" bundle:nil]
         forCellReuseIdentifier:@"SeafDirCell"];

    if([self respondsToSelector:@selector(edgesForExtendedLayout)])
        self.edgesForExtendedLayout = UIRectEdgeNone;
    if ([self.directory isKindOfClass:[SeafRepos class]]) {
        [self.navigationItem setHidesBackButton:YES];
    } else
        [self.navigationItem setHidesBackButton:NO];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:STR_CANCEL style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    self.tableView.scrollEnabled = YES;
    UIBarButtonItem *flexibleFpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.chooseItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"OK", @"Seafile") style:UIBarButtonItemStylePlain target:self action:@selector(chooseFolder:)];
    NSArray *items = [NSArray arrayWithObjects:flexibleFpaceItem, self.chooseItem, flexibleFpaceItem, nil];
    [self setToolbarItems:items];
    self.title = _directory.name;

    __weak typeof(self) weakSelf = self;
    [self.tableView addPullToRefreshWithActionHandler:^{
        if (![weakSelf checkNetworkStatus]) {
            [weakSelf performSelector:@selector(doneLoadingTableViewData) withObject:nil afterDelay:0.1];
            return;
        }

        weakSelf.directory.delegate = weakSelf;
        [weakSelf.directory loadContent:YES];
    }];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.navigationController setToolbarHidden:NO];
    if (!_chooseRepo && [_directory isKindOfClass:[SeafRepos class]]) {
        [self.chooseItem setEnabled:NO];
    } else if (_chooseRepo)
        [self.navigationController setToolbarHidden:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return NSLocalizedString(@"Choose", @"Seafile");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    int i;
    for (i = 0; i < _directory.items.count; ++i) {
        if (![[_directory.items objectAtIndex:i] isKindOfClass:[SeafDir class]]) {
            break;
        }
    }
    return i;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *CellIdentifier = @"SeafDirCell";
    SeafCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *cells = [[NSBundle mainBundle] loadNibNamed:CellIdentifier owner:self options:nil];
        cell = [cells objectAtIndex:0];
    }
    [cell reset];

    @try {
        SeafDir *sdir = [_directory.items objectAtIndex:indexPath.row];
        cell.textLabel.text = sdir.name;
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.imageView.image = sdir.icon;
        cell.detailTextLabel.text = @"";
        if ([sdir isKindOfClass:[SeafRepo class]]) {
            SeafRepo *repo = (SeafRepo *)sdir;
            if (repo.isGroupRepo) {
                cell.detailTextLabel.text = repo.owner;
            }
        }
    } @catch(NSException *exception) {
    }
    return cell;
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    @try {
        _curDir = [_directory.items objectAtIndex:indexPath.row];
    } @catch(NSException *exception) {
        [self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
        return;
    }
    if (![_curDir isKindOfClass:[SeafDir class]])
        return;
    if (_chooseRepo) {
        [self.delegate chooseDir:self dir:_curDir];
        return;
    }
    if ([_curDir isKindOfClass:[SeafRepo class]] && [(SeafRepo *)_curDir passwordRequired]) {
        [self popupSetRepoPassword:(SeafRepo *)_curDir];
        return;
    }
    SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:_curDir delegate:self.delegate chooseRepo:false];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)popupSetRepoPassword:(SeafRepo *)repo
{
    [self popupSetRepoPassword:repo handler:^{
        [SVProgressHUD dismiss];
        SeafDirViewController *controller = [[SeafDirViewController alloc] initWithSeafDir:repo delegate:self.delegate chooseRepo:false];
        [self.navigationController pushViewController:controller animated:YES];
    }];
}

#pragma mark - SeafDentryDelegate
- (void)download:(SeafBase *)entry progress:(float)progress
{

}
- (void)download:(SeafBase *)entry complete:(BOOL)updated
{
    [self doneLoadingTableViewData];
    if (updated && [self isViewLoaded]) {
        [self.tableView reloadData];
    }
}

- (void)download:(SeafBase *)entry failed:(NSError *)error
{
    [self doneLoadingTableViewData];
    if ([_directory hasCache])
        return;

    [SVProgressHUD showErrorWithStatus:NSLocalizedString(@"Failed to load content of the directory", @"Seafile")];
    [self.tableView reloadData];
    Warning("Failed to load directory content %@\n", _directory.name);
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)doneLoadingTableViewData
{
    [self.tableView.pullToRefreshView stopAnimating];
}
@end
