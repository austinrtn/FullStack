package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/rand/v2"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

const PORT = ":3000"
var lastImgName string = ""

type ClientCategory string 
const (
	UI ClientCategory = "UI"
	Display ClientCategory = "DISPLAY"
)

type BroadcastMsg string 
const (
	Refresh BroadcastMsg = "refresh"
	ConnectionEstablished BroadcastMsg = "connection_established"
	PhotosAvailable BroadcastMsg = "photos_available"
	NoPhotosAvailable BroadcastMsg = "no_photos_available"
)

type Client struct {
	//struct categories: 'ui', 'display'
	Category ClientCategory
}

type ImgData struct {
	/// Used to parse JSON client image data from client 
	FileName string `json:"name"`
	FileBytes []byte `json:"file"`
}

type ImgPath struct {
	// Used to to send / recieve photo file paths JSON formated 
	Path string `json:"path"`
}

type AppState struct {
	PhotoDirName string 
	Clients map[chan BroadcastMsg] Client 
	Mu sync.Mutex
	PhotosAvailable bool
	LastRecordedLen int
}

func updateAppState(appState *AppState, dir []os.DirEntry) {
	appState.Mu.Lock()
	defer appState.Mu.Unlock()

	currentLen := len(dir)

	if !appState.PhotosAvailable && currentLen > 0 {
		broadcastLocked(appState, Display, PhotosAvailable)
		appState.PhotosAvailable = true
	} else if appState.PhotosAvailable && appState.LastRecordedLen > 0 && currentLen == 0 {
		broadcastLocked(appState, Display, NoPhotosAvailable)
		appState.PhotosAvailable = false
	}

	appState.LastRecordedLen = currentLen
}

func openDir(res http.ResponseWriter, dirName string) (files []os.DirEntry, ok bool) {
	files, err := os.ReadDir(dirName)

	if err != nil {
		http.Error(res, "Could not read photos director", http.StatusInternalServerError)	
		return 
	}
	ok = true
	return 
}

func main() {
	var err error
	// Create a static file server using http.FileServer
	fs := http.FileServer(http.Dir("http"))

	// Set root directory
	http.Handle("/", fs)

	photos := http.FileServer(http.Dir("photos"))
	http.Handle("/photos/", http.StripPrefix("/photos", photos))

	appState := &AppState{
		Clients: make(map[chan BroadcastMsg] Client),
		PhotosAvailable: false,
		PhotoDirName: "photos",
		LastRecordedLen: 0,
	}

	err = os.MkdirAll(appState.PhotoDirName, 0755)
	if err != nil {
		log.Fatal("Error creating photos directory on server")
		return
	}

	dir, err := os.ReadDir(appState.PhotoDirName)
	if err != nil {
		log.Fatalf("Error: %v", err)	
		return; 
	}

	updateAppState(appState, dir)

	//Handle functions 
	http.HandleFunc("/events", func(res http.ResponseWriter, req *http.Request){ sseHandler(appState, res, req) })
	http.HandleFunc("/getPhotos", func(res http.ResponseWriter, req *http.Request) { getPhotos(appState, res, req) })
	http.HandleFunc("/savePhoto", func(res http.ResponseWriter, req *http.Request) { savePhoto(appState, res, req) })
	http.HandleFunc("/deletePhoto", func(res http.ResponseWriter, req *http.Request) { deletePhoto(appState, res, req) })
	http.HandleFunc("/getRandomPhoto",func(res http.ResponseWriter, req *http.Request) { getRandomPhoto(appState, res, req) })
	http.HandleFunc("/test", test);

	// Listen to port, handle if error
	log.Printf("Listening to %s\n\n", PORT)
	err = http.ListenAndServe(PORT, nil); if err != nil {
		log.Fatal(err)
	}
}

func test(res http.ResponseWriter, req *http.Request) {
	res.Header().Set("Content-Type", "json")
	res.Header().Set("Test-Header", "Header Recived!")
	
	type Test struct {
		Msg string `json:"msg"`
	}

	t := Test{Msg: "Hello from the otherside"}
	json.NewEncoder(res).Encode(t)
}

/// Function that is ran when client enters server.  Creates string chanel for client 
/// and adds it to the client map.  Then listens for when messages are added to the client's chanel 
/// from server and sends to client until disconnect 
func sseHandler(appState *AppState, res http.ResponseWriter, req *http.Request) {
	// Set headers to ensure stream continues for life time of client-server connection
	res.Header().Set("Content-Type", "text/event-stream")
	res.Header().Set("Cache-Control", "no-cache")
	res.Header().Set("Connection", "keep-alive")

	flusher, ok := res.(http.Flusher)
	if !ok {
		http.Error(res, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	categoryStr := req.URL.Query().Get("category")
	category := ClientCategory(strings.ToUpper(categoryStr))

	// Add client chanel to client map.  Lock map to ensure 'single file' adding of Clients.
	// Multiple Clients being connected at the same time without locking map can cause errors.
	ch := make(chan BroadcastMsg, 1)
	appState.Mu.Lock()
	appState.Clients[ch] = Client{Category: category}
	appState.Mu.Unlock()

	fmt.Println("New connection established...")

	defer func() {
		appState.Mu.Lock()
		delete(appState.Clients, ch)
		appState.Mu.Unlock()
	}()

	broadcastToClient(res, flusher, ConnectionEstablished)
	if category == Display {
		if appState.PhotosAvailable {
			broadcastToClient(res, flusher, PhotosAvailable)
		} else {
			broadcastToClient(res, flusher, NoPhotosAvailable)
		}
	}

	// Listen for messages to be added to the client's chanel, then flush it to the client 
	for {
		select {
		case msg := <-ch:
			broadcastToClient(res, flusher, msg)
		case <-req.Context().Done():
			return
		}
	}
}

func broadcastToClient(res http.ResponseWriter, flusher http.Flusher, msg BroadcastMsg) {
	fmt.Fprintf(res, "%s", wrapData(string(msg)))
	flusher.Flush()
}

/// adds server message to client chanel that JS frontend listens for 
func broadcast(appState *AppState, clientCategory ClientCategory, msg BroadcastMsg) {
	// Lock from adding clients to client map to not modify
	// map while itereating through it 
	appState.Mu.Lock()
	defer appState.Mu.Unlock()
	broadcastLocked(appState, clientCategory, msg)
}

/// Must be wrapped in AppState.Mu lock / unlock.  See broadcast function for example 
func broadcastLocked(appState *AppState, clientCategory ClientCategory, msg BroadcastMsg) {
	// For each client chanel, send message through it 

	for ch := range appState.Clients {
		if clientCategory == "" || clientCategory == appState.Clients[ch].Category{
			select {
				case ch <- msg:
				default: 
			}
		}
	}
}

/// Sends list of photofile paths to client to load into HTML 
func getPhotos(appState *AppState, res http.ResponseWriter, _ *http.Request) {
	res.Header().Set("Content-Type", "application/json")
	res.Header().Set("Cache-Control", "no-cache")
	
	dir, ok := openDir(res, appState.PhotoDirName)
	if !ok { return }
	
	updateAppState(appState, dir)
	if !appState.PhotosAvailable { return }

	// Store imagePath structs to be converted into JSON 
	var imgPaths []ImgPath

	// For each file, create file path, convert into ImgPath struct and append to imgPaths
	for _, file := range dir {
		if logError(nil, checkImgValid(file.Name(), file.IsDir())) { return }

		// Create photo filepath 
		filePath := filepath.Join("photos", file.Name())

		imgData := ImgPath{
			Path: filePath,
		}

		imgPaths = append(imgPaths, imgData)
	}

	// Send imgPaths to http response writer as JSON 
	json.NewEncoder(res).Encode(imgPaths)
}

/// Saves photo selected and send from JS client to File Server
func savePhoto(appState *AppState, res http.ResponseWriter, req *http.Request) {
	// Create data instance to save JSON to
 	var imgData ImgData
        var err error
        // Decode json from req.BODY
        err = json.NewDecoder(req.Body).Decode(&imgData)
        // Check if JSON parsed
        if err != nil {
                http.Error(res, "Error parsing JSON", http.StatusBadRequest)
                return
        }
        defer req.Body.Close()

	// Write bytes to file with permisions 
	fileName := appState.PhotoDirName + "/" + filepath.Base(imgData.FileName)
	
	err = os.WriteFile(fileName, imgData.FileBytes, 0644)
	if err != nil {
		http.Error(res, "Error writing file", http.StatusBadRequest)
		return
	}

	dir, ok := openDir(res, appState.PhotoDirName)
	if !ok { return }
	updateAppState(appState, dir)

	log.Printf("File '%s' downloaded!", imgData.FileName) 
}


func deletePhoto(appState *AppState, res http.ResponseWriter, req *http.Request) {
	var imgPath ImgPath	

	// Get path from JSON sent by client 
	json.NewDecoder(req.Body).Decode(&imgPath)
	err := os.Remove(imgPath.Path)

	if logError(nil, err) { return }

	dir, ok := openDir(res, appState.PhotoDirName)
	if !ok { return}
	updateAppState(appState, dir)
}

func getRandomPhoto(appState *AppState, res http.ResponseWriter, _ *http.Request) {
	dir, ok := openDir(res, appState.PhotoDirName)
	if !ok { return }

	updateAppState(appState, dir)

	if !appState.PhotosAvailable {
		http.Error(res, "No photos photos_available", http.StatusNotFound)
		return 
	}
			
	var randFile os.DirEntry
	var filePath string 
	for {
		randFile = dir[rand.IntN(len(dir))] 
		filePath = filepath.Join("photos", randFile.Name())

		if len(dir) > 1 && lastImgName != randFile.Name() { 
			lastImgName = randFile.Name()
			break 
		} else { break } 
	}

	fileExt := filepath.Ext(filePath)
	res.Header().Set("Content-Type", mime.TypeByExtension(fileExt))
	res.Header().Set("X-File-Name", randFile.Name())

	fileData, err := os.ReadFile(filePath)

	if err != nil {
		http.Error(res, "Was unable to read requested file", http.StatusInternalServerError)
		return 
	}

	res.Write(fileData)
}

func logError(msg *string, err error) bool {
	if err == nil { return false}
	if msg == nil {
		log.Printf("Error: %v\n", err)
	} else {
		log.Printf("%v %v\n", msg, err)
	}

	return true
}

func wrapData(data string) string {
	str := fmt.Sprintf("data::%s\n\n", data)
	return str
}

var errInvalidFile = errors.New("invalid image type")

func checkImgValid(fileName string, isDir bool) (error) {
	if isDir { return errInvalidFile}
	fileExt := filepath.Ext(fileName)

	if fileExt != ".png" && fileExt != ".jpg" && fileExt != ".jpeg" { return errInvalidFile}
	return nil
}

