import tkinter as tk
import pyttsx3
import threading

def update_timer():
    global count, running, paused
    if running and not paused and count >= 0:
        if count < 4:
            label.config(text="计时器：%d 秒" % count, fg="red")
            if count == 3:
                thread = threading.Thread(target=speak_countdown, args=(count,))
                thread.start()
        else:
            label.config(text="计时器：%d 秒" % count, fg="black")
        count -= 1
        root.after(1000, update_timer)
    elif running and not paused and count < 0:
        count = int(interval_entry.get())
        update_timer()

def start_timer():
    global count, running, paused
    running = True
    paused = False
    count = int(interval_entry.get())
    update_timer()

def stop_timer():
    global running
    running = False
    label.config(text="计时器：已停止", fg="black")

def set_interval():
    try:
        interval = int(interval_entry.get())
        if interval >= 1:
            interval_entry.delete(0, tk.END)
            interval_entry.insert(0, interval)
    except ValueError:
        pass

def toggle_pause():
    global paused
    paused = not paused

def activate_start_button(event):
    start_timer()

def speak_countdown(countdown):
    if countdown > 0:
        engine.say(str(countdown))
        engine.runAndWait()
        speak_countdown(countdown - 1)

# Initialize text-to-speech engine
engine = pyttsx3.init()

count = 20
running = False
paused = False

root = tk.Tk()
root.title("计时器")
root.geometry("300x200")

label = tk.Label(root, text="计时器：%d 秒" % count, font=("Arial", 20))
label.pack(pady=20)

interval_label = tk.Label(root, text="设定计时间隔（秒）：")
interval_label.pack()

interval_entry = tk.Entry(root)
interval_entry.insert(0, count)  # Set default interval value to 20 seconds
interval_entry.pack()

set_interval_button = tk.Button(root, text="设定间隔", command=set_interval)
set_interval_button.pack()

start_button = tk.Button(root, text="开始计时", command=start_timer)
start_button.pack()

stop_button = tk.Button(root, text="停止计时", command=stop_timer)
stop_button.pack()

pause_button = tk.Button(root, text="暂停计时", command=toggle_pause)
pause_button.pack()

# Bind F11 key to toggle pause
root.bind("<F11>", lambda event: toggle_pause())

# Bind F12 key to activate the start_button
root.bind("<F12>", activate_start_button)

root.mainloop()
