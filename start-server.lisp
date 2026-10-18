;; start-server.lisp

;; 必要なライブラリと、自分のシラバスプログラムをロードする
(load "housou-syllabus-db-server.lisp") 

(if (probe-file *filepath*)
    (progn
      (format t "Auto-loading syllabus DB from ~A...~%" *filepath*)
      (load-syllabus-db *filepath*))
    (progn
      (format t "Warning: DB file ~A not found. Starting with empty DB.~%" *filepath*)
      (update-all-syllabus-db)
      (save-syllabus-db *filepath*)))
    
;; Swank（通信サーバー）をロード
(ql:quickload :swank)

;; ポート4005でサーバーを立ち上げ、接続が切れても終了しない（:dont-close t）ようにする
(swank:create-server :port 4005 :dont-close t)

(format t "Swank server is running on port 4005...~%")

;; プロセスが終了しないように無限ループで待機させる
(loop (sleep 3600))

