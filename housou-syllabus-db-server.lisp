;; ここから下に defstruct や defun update-syllabus-db を書く
(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :dexador)     
  (ql:quickload :split-sequence) 
  (ql:quickload :plump)
  (ql:quickload :clss)
  (ql:quickload :cl-cookie)  
  (print "Loaded!"))   


(defparameter *user-agent*
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  "WAKABA（シラバス）へのアクセス時に送る User-Agent。")

(defparameter *urls*
  '("https://www.ouj.ac.jp/kamoku/kyouyou/C/kiban_kiban/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/kiban_gaikokugo/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/kiban_hokentaiku/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/seikatu/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/sinri/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/syakai/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/ningen/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/joho/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/shizen/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/kango/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/sotuken/"
 "https://www.ouj.ac.jp/kamoku/kyouyou/C/shisyo/")
  "科目一覧を取得する教養学部のカテゴリページ。")

(defparameter *filepath* "db.lispdata"
  "シラバス DB の保存先（作業ディレクトリからの相対パス）。")

;; 1. 構造体の定義
(defstruct syllabus
  "1科目分のシラバス情報。"
  name
  url
  code
  lead-instructor
  offering-year
  lecture-titles)

;; 2. 動的配列の定義（スペルを :adjustable に修正）
(defparameter *syllabus-db* (make-array 0 :adjustable t :fill-pointer 0)
  "シラバス DB 本体。syllabus 構造体の可変長ベクタ。")

;; 3. データベース更新関数
(defun update-all-syllabus-db ()
  "指定したURLsから講義データを抽出し、*syllabus-db* を更新する"
(setf (fill-pointer *syllabus-db*) 0)
(dolist (url *urls*)
  (format t "Scanning: ~A...~%" url)
  (update-syllabus-db url))
(format t "All Done! Total items: ~D~%" (length *syllabus-db*)))

(defun update-syllabus-db (url)
"urlから講義データを取得し、追加する"
  (let* ((html-string (dex:get url))
         (root (plump:parse html-string))
         (all-items (clss:select "li.CourseItem_c10oi56" root)))
  
    ;; データを追加するだけなので do を使用
    (loop for item across all-items
          do (let* ((a-tag (elt (clss:select "p.text-baseSize a" item) 0))
                    (course-name (plump:text a-tag))
                    (course-url (plump:attribute a-tag "href"))
                    (wrappers (clss:select "div.SubTextWrap_sdg736o" item))
                    (subject-code (plump:text (elt (clss:select "p" (elt wrappers 0)) 1)))
                    (subject-lead-instructor (plump:text (elt (clss:select "p" (elt wrappers 1)) 1)))
                    (subject-offering-year (plump:text (elt (clss:select "p" (elt wrappers 2)) 1)))
		    (subject-lecture-titles (get-lecture-titles course-url)))
               
               ;; vector-push-extend に対象のベクター *syllabus-db* を追加
               (vector-push-extend (make-syllabus :name course-name
                                                  :url course-url
                                                  :code subject-code
						  :lead-instructor subject-lead-instructor
						  :offering-year subject-offering-year
						  :lecture-titles subject-lecture-titles )
				   *syllabus-db*)))
    ;; 更新件数を表示
    (format t "DB updated: ~A items found.~%" (length *syllabus-db*))))


(defun clean-url (url)
  "HTMLエンティティの &amp; を正しい & に置換する"
  (cl-ppcre:regex-replace-all "&amp;" url "&"))

(defun fetch-wakaba-page (raw-url)
  "WAKABAのセキュリティを通過するためのフェッチ関数"
  ;; let* のブロックを開く
  (let* ((cleaned-url (clean-url raw-url))
         (cookie-jar (cl-cookie:make-cookie-jar)))
    
    ;; --- ここから let* の中身（スコープ内） ---

    ;; 1回目のアクセス（ダミー）
    (dex:get cleaned-url
             :cookie-jar cookie-jar
             :headers `((:user-agent . ,*user-agent*))) 
    
    ;; 2回目のアクセス（本命）
    (let ((real-url "https://www.wakaba.ouj.ac.jp/kyoumu/syllabus/PU02060200211/initialize.do"))
      (dex:post real-url
                :cookie-jar cookie-jar
                :headers `((:user-agent . ,*user-agent*)
                           (:referer . ,cleaned-url))))))

(defun get-lecture-titles (url)
  "講義のタイトル名を取得する"
  (let* ((html-string (fetch-wakaba-page url))
          (root (plump:parse html-string))
          (all-items (clss:select "table.ttb_entry p" root)))
    (loop for item across all-items
          ;; string-trim で取り除きたい文字のリストを指定する
          collect (string-trim '(#\Space #\Tab #\Newline #\Return) 
                               (plump:text item)))))

;; 4. データベース表示関数
(defun save-syllabus-db (filepath)
  "DBをファイルにシリアライズする"
  (with-open-file (out filepath
		       :direction :output
		       :if-exists :supersede
		       :external-format :utf-8)
    (let ((*print-readably* t))
      (print *syllabus-db* out)))
  (format t "Saved to ~A~%" filepath))

(defun load-syllabus-db (filepath)
  "ファイル FILEPATH から DB を読み込み、*syllabus-db* を置き換える"
  (with-open-file (in filepath
		      :direction :input
		      :external-format :utf-8)
    (setf *syllabus-db* (read in)))
  (format t "Loaded ~D items form ~A~%" (length *syllabus-db*) filepath))
		  
(defun init ()
  "DB を初期化する。*filepath* があれば読み込み、なければ全カテゴリを取得して保存する"
  (if (probe-file *filepath*)
    (progn
      (format t "Auto-loading syllabus DB from ~A...~%" *filepath*)
      (load-syllabus-db *filepath*))
    (progn
      (format t "Warning: DB file ~A not found. Starting with empty DB.~%" *filepath*)
      (update-all-syllabus-db)
      (save-syllabus-db *filepath*))))


(defun show-syllabus-db ()
  "現在 *syllabus-db* に格納されている内容を一覧表示する"
  (format t "~V@{~A~:*~}~%" 60 "-") ; 区切り線
  (format t "~&~10A | ~7A | ~A~%" "Code" "Name" "URL")
  (format t "~V@{~A~:*~}~%" 60 "-")
  
  (loop for s across *syllabus-db*
        do (format t "~10A | ~30A | ~A~%" 
                   (syllabus-code s) 
                   (syllabus-name s) 
                   (syllabus-url s)))
  (format t "~V@{~A~:*~}~%" 60 "-"))


(defun find-name-by-code (code)
  "指定したコードに合致する講義名を探して返す"
  (let ((found (find-if (lambda (s)
                          (string= (syllabus-code s) code))
                        *syllabus-db*)))
    (if found
        (syllabus-name found) ; 見つかったら名前を返す
        "Not Found")))         ; 見つからなかった場合

(defun find-syllabus-by-code (code)
  "指定したコードに合致する講義内容を探して返す"
  (let ((found (find-if (lambda (s)
                          (string= (syllabus-code s) code))
                        *syllabus-db*)))
    (if found
        found ; 見つかったらsyllabusを返す
        "Not Found")))         ; 見つからなかった場合


;; Emacs call generate-notes-method
(defun clean-text (str)
  "全角スペースを半角スペースに置換し、前後の不要な空白をトリミングする"
  (if (stringp str)
      (let* ((replaced (cl-ppcre:regex-replace-all "　" str " ")))
        (string-trim '(#\Space #\Tab #\Newline #\Return) replaced))
      str))

(defun generate-org-note (syllabus)
  "Syllabus構造体を受け取り、Org-modeフォーマットの文字列を生成する"
  (with-output-to-string (out)
    (format out "#+STARTUP: showall~%")
    (format out "* Overview~%")
    (format out "- code            : ~A~%" (clean-text (syllabus-code syllabus)))
    (format out "- name            : ~A~%" (clean-text(syllabus-name syllabus)))
    (format out "- lead-instructor : ~A~%" (clean-text(syllabus-lead-instructor syllabus)))
    (format out "- offering-year   : ~A~%~%"(clean-text (syllabus-offering-year syllabus)))
    (format out "* Todo [/]~%")    
    (format out ":PROPERTIES:~%")
    (format out ":COLUMNS: %ID %ITEM %TODO %単位 %NOTE %Effort %CLOCKSUM~%")
    (format out ":VISIBILITY: content~%")
    (format out ":END:~%")
    (format out "** Progress~%")
    (format out "#+BEGIN: columnview :hlines 1 :id local  :maxlevel 3~%")
    (format out "#+END:~%")
    ;; lecture-titles のリストをループして TODO を生成
    (format out "** Course~%")
    (loop for title in (syllabus-lecture-titles syllabus)
	  do
	     (format out "*** TODO ~A~%" (clean-text title))
	     (format out ":PROPERTIES:~%")
	     (format out ":Effort:   1:00~%")
	     (format out ":END:~%"))
	     
    (format out "** TODO 自習問題~%")
    (format out "** TODO web提出課題~%")
    (format out "** TODO 単位認定試験~%")
    (format out "~%* Note~%")))

(defun generate-note (code)
  "科目コード CODE の科目ノート（org）を返す。該当がなければ \"Not Found\""
  (let ((found (find-if (lambda (s)
			  (string= (syllabus-code s) code))
			*syllabus-db*)))
    (if found
	(generate-org-note found)
	"Not Found")))


(defun org-get-course (syllabus)
  "Syllabus構造体を受け取り、講義タイトルを Org の TODO 見出しにした文字列を返す"
  (with-output-to-string (out)
    ;; lecture-titles のリストをループして TODO を生成
    (loop for title in (syllabus-lecture-titles syllabus)
	  do (format out "** TODO ~A~%" (clean-text title)))))
		

(defun get-course (code)
  "科目コード CODE の講義タイトルを TODO 見出しにした文字列を返す。該当がなければ \"Not Found\""
  (let ((found (find-if (lambda (s)
			  (string= (syllabus-code s) code))
			*syllabus-db*)))
    (if found
	(org-get-course  found)
	"Not Found")))



(defun emacs-callback-function (func code)
  "Emacs から呼ぶ入口。DB を読み直してから FUNC に応じた文字列を返す。
FUNC が \"generate-note\" なら科目ノート、\"get-course\" なら講義タイトルの TODO 見出し。
該当する科目がなければ \"Not Found\"、FUNC が不明なら \"Not found function\" を返す"
  (cond
    ((string= func "generate-note")
     (progn
       (init)
       (clean-text (generate-note code))))
    ((string= func "get-course")
     (progn
       (init)
       (clean-text (get-course code))))
     (t "Not found function")))
      
