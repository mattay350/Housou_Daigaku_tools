;;;; gen-readme.lisp --- README.md の API 節をソースの docstring から生成する
;;;;
;;;; 使い方（このディレクトリで）:
;;;;   ros run --load gen-readme.lisp
;;;;
;;;; housou-syllabus-db-server.lisp をロードせずに読み（read）、defstruct /
;;;; defparameter / defvar / defun の名前・引数・docstring を取り出して、
;;;; README.md の BEGIN/END マーカーの間だけを書き換える。
;;;; 先頭の eval-when（ql:quickload）だけは評価する。依存ライブラリの
;;;; パッケージ（dex: など）が無いと、ソースを read できないため。

(defpackage :gen-readme
  (:use :cl)
  (:export #:main))
(in-package :gen-readme)

(defparameter *here*
  (make-pathname :name nil :type nil
                 :defaults (or *load-truename* *default-pathname-defaults*))
  "このスクリプトがあるディレクトリ。")

(defparameter *source* "housou-syllabus-db-server.lisp"
  "API を取り出すソースファイル。")

(defparameter *readme* "README.md"
  "書き換える README。")

(defparameter *begin-marker* "<!-- BEGIN GENERATED: API -->")
(defparameter *end-marker* "<!-- END GENERATED: API -->")

(defparameter *external-format* #+clisp charset:utf-8 #-clisp :utf-8)

;;; ----------------------------------------------------------------------
;;; ソースの読み取り
;;; ----------------------------------------------------------------------
(defun read-forms (path)
  "PATH のトップレベルフォームを順に read して返す。eval-when だけは評価する。"
  (with-open-file (in path :external-format *external-format*)
    (let ((*package* (find-package :cl-user))
          (*read-eval* nil)
          (eof (gensym)))
      (loop for form = (read in nil eof)
            until (eq form eof)
            when (and (consp form) (eq (first form) 'eval-when))
              do (eval form)
            collect form))))

(defun body-doc (body)
  "関数本体 BODY の先頭が docstring なら返す（後ろに式が続く場合だけ）。"
  (when (and (stringp (first body)) (rest body))
    (first body)))

(defun form-entry (form)
  "トップレベルフォーム FORM を (種類 名前 詳細 docstring) にする。対象外なら nil。"
  (when (consp form)
    (case (first form)
      (defun
       (destructuring-bind (name lambda-list &rest body) (rest form)
         (list :function name lambda-list (body-doc body))))
      ((defparameter defvar)
       (destructuring-bind (name &optional (value nil value-p) doc) (rest form)
         (list :variable name (and value-p value) (and (stringp doc) doc))))
      (defstruct
       (destructuring-bind (name-and-options &rest rest) (rest form)
         (let* ((doc (and (stringp (first rest)) (rest rest) (first rest)))
                (slots (if doc (rest rest) rest)))
           (list :struct
                 (if (consp name-and-options) (first name-and-options) name-and-options)
                 (mapcar (lambda (s) (if (consp s) (first s) s)) slots)
                 doc)))))))

;;; ----------------------------------------------------------------------
;;; Markdown の生成
;;; ----------------------------------------------------------------------
(defun lower (object)
  "OBJECT を cl-user から見た表記（キーワードのコロン付き）で小文字にして返す。"
  (let ((*package* (find-package :cl-user)))
    (string-downcase (prin1-to-string object))))

(defun escape-html (text)
  "Markdown で実体参照として解釈されないよう & < > をエスケープする。"
  (with-output-to-string (out)
    (loop for c across text
          do (case c
               (#\& (write-string "&amp;" out))
               (#\< (write-string "&lt;" out))
               (#\> (write-string "&gt;" out))
               (t (write-char c out))))))

(defun quote-earmuffs (text)
  "TEXT 中の *foo* をコード表記にする（Markdown の強調にならないように）。"
  (with-output-to-string (out)
    (loop with start = 0
          for open = (position #\* text :start start)
          for close = (and open (position #\* text :start (1+ open)))
          do (if (and close
                      (> close (1+ open))
                      (notany (lambda (c) (member c '(#\Space #\Tab #\Newline)))
                              (subseq text open close)))
                 (progn
                   (write-string text out :start start :end open)
                   (format out "`~A`" (subseq text open (1+ close)))
                   (setf start (1+ close)))
                 (progn
                   (write-string text out :start start)
                   (loop-finish))))))

(defun doc-text (doc)
  "docstring を Markdown の段落にする。各行の先頭の空白は除く。"
  (if doc
      (format nil "~{~A~^~%~}"
              (mapcar (lambda (line)
                        (quote-earmuffs
                         (escape-html (string-left-trim '(#\Space #\Tab) line))))
                      (split-lines doc)))
      "（説明なし）"))

(defun split-lines (string)
  (loop for start = 0 then (1+ end)
        for end = (position #\Newline string :start start)
        collect (subseq string start end)
        while end))

(defun value-text (value)
  "変数の初期値を短く表す。"
  (typecase value
    (string (format nil "初期値: `~S`" value))
    (number (format nil "初期値: `~A`" value))
    (cons (if (eq (first value) 'quote)
              (format nil "初期値: ~D 要素のリスト"
                      (length (second value)))
              (format nil "初期値: `~A`" (lower value))))
    (t "")))

(defun write-api (entries out)
  "ENTRIES を種類ごとの Markdown 節にして OUT に書く。"
  (flet ((section (kind title)
           (let ((items (remove-if-not (lambda (e) (eq (first e) kind)) entries)))
             (when items
               (format out "~%### ~A~%" title)
               (dolist (item items)
                 (destructuring-bind (kind name detail doc) item
                   (ecase kind
                     (:struct
                      (format out "~%#### `~A`~%~%~A~%~%スロット: ~{`~A`~^, ~}~%"
                              (lower name) (doc-text doc) (mapcar #'lower detail)))
                     (:variable
                      (format out "~%#### `~A`~%~%~A~%~@[~%~A~%~]"
                              (lower name) (doc-text doc)
                              (let ((v (value-text detail)))
                                (and (plusp (length v)) v))))
                     (:function
                      (format out "~%#### `(~A~{ ~A~})`~%~%~A~%"
                              (lower name) (mapcar #'lower detail)
                              (doc-text doc))))))))))
    (format out "~%<!-- このマーカーの間は gen-readme.lisp が生成する。手で編集しない。 -->~%")
    (section :struct "構造体")
    (section :variable "変数")
    (section :function "関数")
    (terpri out)))

;;; ----------------------------------------------------------------------
;;; README の書き換え
;;; ----------------------------------------------------------------------
(defun file-string (path)
  (with-open-file (in path :external-format *external-format*)
    (let* ((buf (make-string (file-length in)))
           (n (read-sequence buf in)))
      (subseq buf 0 n))))

(defun replace-between (text begin end new)
  "TEXT の BEGIN と END の間を NEW に置き換える。"
  (let* ((b (search begin text))
         (e (and b (search end text :start2 b))))
    (unless (and b e)
      (error "README にマーカー ~S / ~S が見つかりません" begin end))
    (concatenate 'string
                 (subseq text 0 (+ b (length begin)))
                 new
                 (subseq text e))))

(defun main ()
  (let* ((source (merge-pathnames *source* *here*))
         (readme (merge-pathnames *readme* *here*))
         (entries (remove nil (mapcar #'form-entry (read-forms source))))
         (api (with-output-to-string (out) (write-api entries out)))
         ;; 書き込み用に開く前に読み終えておく（:supersede で中身が消えるため）
         (text (replace-between (file-string readme)
                                *begin-marker* *end-marker* api)))
    (with-open-file (out readme :direction :output :if-exists :supersede
                                :external-format *external-format*)
      (write-string text out))
    (format t "~&~A を更新しました（構造体 ~D / 変数 ~D / 関数 ~D）~%"
            (namestring readme)
            (count :struct entries :key #'first)
            (count :variable entries :key #'first)
            (count :function entries :key #'first))))

(main)

;; スクリプトとして実行したときだけ終了する。SLIME の REPL から load した場合は
;; イメージを落とさない。
(unless (find-package :swank)
  #+sbcl (sb-ext:exit)
  #+clisp (ext:quit))
