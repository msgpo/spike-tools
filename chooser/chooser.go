package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os/exec"
	"path"
	"time"

	nc "github.com/rthornton128/goncurses"
)

type Chooser struct {
	scr *nc.Window
}

func (c *Chooser) Init() error {
	var err error
	c.scr, err = nc.Init()
	if err != nil {
		return err
	}

	nc.Raw(true)
	nc.Echo(false)
	nc.Cursor(0)
	c.scr.Timeout(0)
	c.scr.Clear()
	c.scr.Keypad(true)

	return nil
}

func (c *Chooser) Deinit() {
	nc.End()
}

type MenuOption struct {
	text    string
	handler func(*Chooser, ...interface{})
}

func (c *Chooser) DisplayMenu(title string, timeout int, options []MenuOption) (int, error) {
	c.scr.Clear()
	c.scr.Println(title)

	items := make([]*nc.MenuItem, len(options))
	for i, option := range options {
		items[i], _ = nc.NewItem(option.text, "")
		defer items[i].Free()
	}

	menu, err := nc.NewMenu(items)
	if err != nil {
		return 0, err
	}
	defer menu.Free()

	win, err := nc.NewWindow(10, 40, 2, 0)
	if err != nil {
		return 0, err
	}
	win.Keypad(true)

	menu.SetWindow(win)
	menu.SubWindow(win.Derived(5, 36, 1, 3))
	menu.Mark("> ")

	c.scr.Refresh()

	menu.Post()
	defer menu.UnPost()
	win.Refresh()

	countch := make(chan int)
	keych := make(chan nc.Key)

	if timeout > 0 {
		go countdown(countch, timeout)
	}
	go readkey(keych, win)

	for {
		select {
		case ch := <-keych:
			nc.Update()

			switch nc.KeyString(ch) {
			case "enter":
				return menu.Current(nil).Index(), nil
			case "down":
				menu.Driver(nc.REQ_DOWN)
			case "up":
				menu.Driver(nc.REQ_UP)
			}
			win.Refresh()
		case t := <-countch:
			win.MovePrint(8, 0, fmt.Sprintf("Time to select: %2d ", t))
			win.Refresh()
			if t == 0 {
				return menu.Current(nil).Index(), nil
			}
		}
	}
}

//

func main() {
	title := flag.String("title", "Choose the recovery version", "Menu title")
	output := flag.String("output", "/run/chooser.out", "Output file location")
	seed := flag.String("seed", "/run/ubuntu-seed", "Ubuntu-seed location")
	timeout := flag.Int("timeout", 5, "Timeout in seconds")
	check := flag.Bool("check", false, "Check if magic trigger is active")
	flag.Parse()

	// Wait for trigger to run the chooser
	if *check && !checkTrigger() {
		return
	}

	c := &Chooser{}
	c.Init()
	defer c.Deinit()

	if !*check {
		chooseSystem(c, *title, *seed, *output, *timeout)
		return
	}

	mainMenu := []MenuOption{
		{"Run", runHandler},
		{"Recover", recoverHandler},
		{"Reset", resetHandler},
		{"Advanced", advancedHandler},
	}

	opt, err := c.DisplayMenu("Choose mode", 0, mainMenu)
	if err != nil {
		c.Deinit()
		log.Fatalf("internal error: %s", err)
	}
	mainMenu[opt].handler(c, *seed, *output)
}

func checkTrigger() bool {
	fmt.Println("Checking recovery trigger...")
	time.Sleep(2 * time.Second)
	return exec.Command("/bin/check-trigger").Run() == nil
}

func runHandler(c *Chooser, parms ...interface{}) {
	// do nothing
}

func recoverHandler(c *Chooser, parms ...interface{}) {
	// set system to boot in recover mode
}

func resetHandler(c *Chooser, parms ...interface{}) {
	// restore to factory?
}

func advancedHandler(c *Chooser, parms ...interface{}) {
	// allow user to choose an action for a recovery version
	seed := parms[0].(string)
	output := parms[1].(string)
	chooseSystem(c, "Choose a recovery system:", seed, output, 0)
}

func chooseSystem(c *Chooser, title, seedDir, output string, timeout int) string {
	versions, err := getRecoveryVersions(seedDir)
	if err != nil {
		log.Fatalf("cannot get recovery versions: %s", err)
	}

	versionOptions := make([]MenuOption, len(versions))
	for i, ver := range versions {
		versionOptions[i] = MenuOption{ver, nil}
	}

	index, err := c.DisplayMenu(title, timeout, versionOptions)
	if err != nil {
		log.Fatalf("cannot display menu: %s", err)
	}
	version := versionOptions[index].text

	if len(output) > 0 {
		config := fmt.Sprintf("uc_recovery_system=%q", version)
		if err := ioutil.WriteFile(output, []byte(config), 0644); err != nil {
			c.Deinit()
			log.Fatalf("cannot write configuration file: %s", err)
		}
	}

	return version
}

func readkey(keych chan nc.Key, win *nc.Window) {
	for {
		keych <- win.GetChar()
	}
}

func countdown(countch chan int, val int) {
	for val >= 0 {
		countch <- val
		val--
		time.Sleep(1 * time.Second)
	}
}

func getRecoveryVersions(mnt string) ([]string, error) {
	files, err := ioutil.ReadDir(path.Join(mnt, "systems"))
	if err != nil {
		return []string{}, fmt.Errorf("cannot read recovery list: %s", err)
	}
	list := make([]string, len(files))
	for i, f := range files {
		list[i] = f.Name()
	}
	return list, nil
}
