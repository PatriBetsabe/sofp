#!/bin/bash

# Requires pdftk and lyx.
# Get lyx from www.lyx.org
# For Mac, get pdftk from https://www.pdflabs.com/tools/pdftk-the-pdf-toolkit/pdftk_server-2.02-mac_osx-10.11-setup.pkg

name="sofp"

function git_commit_hash {
	git rev-parse HEAD # Do not use --short here.
}

function source_hash {
	cat $0 $name*.lyx | shasum -a 256 | cut -c 1-64
}

# Make a PDF package with embedded source archive.

function run_latex_many_times {
	local base="$1"
	echo "LaTeX Warning - Rerun" > "$base.log"
	while grep -q '\(LaTeX Warning.*Rerun\|^(rerunfilecheck).*Rerun\)' "$base.log"; do
		 latex --interaction=batchmode "$base.tex"
        done # This used to be only pdflatex but now we are using ps2pdf because of pstricks.
}

function make_pdf_with_index {
	local base="$1" fast="$2"
	if [[ -z "$fast" ]]; then
		run_latex_many_times "$base"
		makeindex "$base.idx"
	fi
	run_latex_many_times "$base"
        (dvips "$base.dvi") 2>&1 >> $base.log
        (ps2pdf -dPDFSETTINGS=/prepress -dEmbedAllFonts=true "$base.ps") 2>&1 >> $base.log
}

function add_color {
	local texsrc="$1"
	# Insert color comments into displayed equation arrays. Also, in some places the green color was inserted; replace by `greenunder`.
	# Example of inserted color: {\color{greenunder}\text{outer-interchange law for }M:}\quad &
	LC_ALL=C sed -i "" -e 's|\\color{green}|\\color{greenunder}|; s|^\(.*\\text{[^}]*}.*:\)\( *\\quad \& \)|{\\color{greenunder}\1}\2|' "$texsrc"
	# Insert color background into all displayed equations.
	if false; then
	LC_ALL=C sed -i "" -E -e ' s!\\begin\{(align.?|equation)\}!\\begin{empheq}[box=\\mymathbgbox]{\1}!; s!\\end\{(align.?|equation)\}!\\end{empheq}!; ' "$texsrc"
	LC_ALL=C sed -i "" -E -e ' s!^\\\[$!\\begin{empheq}[box=\\mymathbgbox]{equation*}!; s!^\\\]$!\\end{empheq}!; ' "$texsrc"
	fi
}

function add_source_hashes {
	gitcommit=`git_commit_hash`
	sourcehash=`source_hash`
	echo $sourcehash > $name.source_hash1
	LC_ALL=C sed -i "" -E -e "s/INSERTSOURCEHASH/$sourcehash/; s/INSERTGITCOMMIT/$gitcommit/" $name.tex
	if diff -q $name.source_hash $name.source_hash1 > /dev/null; then
		mv $name.source_hash1 $name.source_hash
		false
	else
		mv $name.source_hash1 $name.source_hash
		true
	fi
}

function remove_lulu {
	local base="$1"
        LC_ALL=C sed -i "" -e 's,^\(.publishers{Published by\),%\1,; s,^\(Published by\),%\1,; s,^\(ISBN:\),%\1,' "$base".tex
}

function add_lulu {
	local base="$1"
        LC_ALL=C sed -i "" -e 's,^%\(.publishers{Published by \),\1,; s,^%\(Published by \),\1,; s,^%\(ISBN:\),\1,' "$base".tex
}

# This requires pdftk to be installed on the path. Edit the next line as needed.
pdftk=`which pdftk`

# LyX needs to be installed for this to work. Edit the next line as needed.
lyx="/Applications/LyX.app/Contents/MacOS/lyx"

echo "Info: Using pdftk from '$pdftk' and lyx from '$lyx'"

draft="$name-draft"
srcbase="sofp-src"

rm -f $name*tex

echo "Exporting LyX files $name.lyx and its child documents into LaTeX..."
"$lyx" --export pdflatex $name.lyx # Exports LaTeX for all child documents as well.
echo "Post-processing LaTeX files..."
## Remove mathpazo. This is a mistake: should not remove it.
#LC_ALL=C sed -i "" -e 's/^.*usepackage.*mathpazo.*$//' sofp.tex
# Replace ugly Palatino quote marks and apostrophes by sans-serif marks.
LC_ALL=C sed -i "" -e " s|'s|\\\\textsf{'}s|g; "' s|``|\\textsf{``}|g; s|“|\\textsf{``}|g; '" s|''|\\\\textsf{''}|g; s|”|\\\\textsf{''}|g;  " sofp*.tex
# Add color to equation displays.
for f in $name*tex; do add_color "$f"; done
if add_source_hashes $name.tex; then
	echo "Creating a full PDF file..."
	make_pdf_with_index "$name" # Output is $name.pdf, main file is $name.tex, and other .tex files are \include'd.
	rm -rf "$srcbase"
	mkdir "$srcbase"
	# Copy the required source files to "$srcbase"/.
	cp ../README.md excluded_words $name*lyx $name*tex $name*dvi `fgrep includegraphics $name*tex | sed -e 's,[^{]*{\([^}]*\)}.*,\1.*,' |while read f; do ls $f ; done` *.sh "$srcbase"/
	tar jcvf "$name-src.tar.bz2" "$srcbase"/
	rm -rf "$srcbase"/
	# Do not attach sources to the main PDF file.
	#"$pdftk" "$name.pdf" attach_files "$name-src.tar.bz2" output "1$name.pdf"
	#mv "1$name.pdf" "$name.pdf"
	# Cleanup.
	tar jcvf "$name-logs.tar.bz2" $name*log $name*ilg $name*idx $name*toc
	echo "Log files are found in $name-logs.tar.bz2"
fi


function kbSize {
 local file="$1"
 ls -l -n "$file"|sed -e 's/  */ /g'|cut -f5 -d ' '
}

function pdfPages {
 local file="$1"
 "$pdftk" "$file" dump_data | fgrep NumberOfPages | sed -e 's,^.* ,,'
}

echo Result is "$name.pdf", size `kbSize "$name.pdf"` bytes, with `pdfPages "$name.pdf"` pages.

# Create the lulu.com draft file by selecting the chapters that have been proofread.
# Also, check page counts.
bash check_and_make_draft.sh

# Attach sources to the draft file.
if test -s $name-src.tar.bz2 && test -s $draft.pdf; then  "$pdftk" $draft.pdf attach_files "$name-src.tar.bz2" output $draft-src.pdf
else
	echo Not attaching sources to draft since no source file $name-src.tar.bz2 is found or no $draft.pdf is found.
fi
if [ x"$1" == x-nolulu ]; then
# Create a pdf file without references to lulu.com and without lulu.com's ISBN.
mv "$name".pdf "$name"-lulu.pdf
remove_lulu $name
make_pdf_with_index "$name" fast
create_draft $name $draft-nolulu.pdf

# The main file "$name".pdf has lulu.com information.
mv "$name"-lulu.pdf "$name".pdf

fi

bash spelling_check.sh

# Cleanup?
#rm -f $name*{idx,ind,aux,dvi,ilg,out,toc,log,ps,lof,lot,data}
