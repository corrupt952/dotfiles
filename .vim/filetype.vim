augroup ftdetect
    " Git
    au BufNewFile,BufRead .gitconfig*           setlocal ft=gitconfig
    " C/C++
    au BufNewFile,BufRead *.c                   setlocal tabstop=4 noexpandtab
    au BufNewFile,BufRead *.cpp                 setlocal tabstop=4 noexpandtab
    au BufNewFile,BufRead *.h                   setlocal tabstop=4 noexpandtab
    " Eruby
    au BufNewFile,BufRead *.erb                 setlocal ft=eruby tabstop=2 shiftwidth=2 expandtab
    " Ruby
    au BufNewFile,BufRead *.rb                  setlocal ft=ruby
    au BufNewFile,BufRead *.ruby                setlocal ft=ruby
    au BufNewFile,BufRead *.rabl                setlocal ft=ruby
    au BufNewFile,BufRead *.rake                setlocal ft=ruby
    au BufNewFile,BufRead *.builder             setlocal ft=ruby
    au BufNewFile,BufRead *.gemspec             setlocal ft=ruby
    au BufNewFile,BufRead Rakefile              setlocal ft=ruby
    au BufNewFile,BufRead Gemfile               setlocal ft=ruby
    au BufNewFile,BufRead Berkshelf             setlocal ft=ruby
    au BufNewFile,BufRead Vagrantfile           setlocal ft=ruby
    au BufNewFile,BufRead Guardfile             setlocal ft=ruby
    au BufNewFile,BufRead Bowerfile             setlocal ft=ruby
    au BufNewFile,BufRead .irbrc                setlocal ft=ruby
    " Yaml
    au BufNewFile,BufRead *.yaml                setlocal ft=yaml
    au BufNewFile,BufRead *.yml                 setlocal ft=yaml
    au BufNewFile,BufRead *.yml.example         setlocal ft=yaml
    au BufNewFile,BufRead *.dig                 setlocal ft=yaml
    au BufNewFile,BufRead *.liquid              setlocal ft=yaml
    au BufNewFile,BufRead .yamllint             setlocal ft=yaml
    " Ansible
    au BufNewFile,BufRead */playbooks/**/*.yml  setlocal tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead */roles/**/*.yml      setlocal tabstop=2 shiftwidth=2 expandtab
    " Web
    au BufNewFile,BufRead *.html                setlocal ft=html tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.htm                 setlocal ft=html tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.tmpl                setlocal ft=html
    au BufNewFile,BufRead *.css                 setlocal tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.js                  setlocal tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.scss                setlocal tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.slim                setlocal ft=slim tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead *.json                setlocal ft=json tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead .babelrc              setlocal tabstop=2 shiftwidth=2 expandtab
    " Apple
    au BufNewFile,BufRead *.sketchplugin        setlocal tabstop=2 shiftwidth=2 expandtab
    " Go
    au BufNewFile,BufRead *.go                  setlocal ft=go
    " Nginx
    au BufNewFile,BufRead */nginx/*.conf        setlocal ft=nginx
    au BufNewFile,BufRead */nginx/*.conf.j2     setlocal ft=nginx
    " Coffeescript
    au BufNewFile,BufRead *.coffee              setlocal ft=coffee tabstop=2 shiftwidth=2 expandtab
    " Vue
    au BufNewFile,BufRead *.vue                 setlocal ft=vue tabstop=2 shiftwidth=2 expandtab
    " Terraform
    au BufNewFile,BufRead *.tf                  setlocal ft=terraform
    " SSH config
    au BufNewFile,BufRead *.ssh/config*         setlocal ft=sshconfig
    " sshd_config
    au BufNewFile,BufRead sshd_config*          setlocal ft=sshdconfig tabstop=2 shiftwidth=2 expandtab
    " SELinux
    au BufNewFile,BufRead *.te                  setlocal tabstop=4 noexpandtab
    " Dockerfile
    au BufNewFile,BufRead Dockerfile            setlocal ft=Dockerfile
    au BufNewFile,BufRead Dockerfile*           setlocal ft=Dockerfile
    " docker-compose.yml
    au BufNewFile,BufRead docker-compose.yml    setlocal ft=yaml.docker-compose tabstop=2 shiftwidth=2 expandtab
    au BufNewFile,BufRead docker-compose.yml*   setlocal ft=yaml.docker-compose tabstop=2 shiftwidth=2 expandtab
    " LTSV
    au BufNewFile,BufRead *.ltsv                setlocal ft=ltsv
    " Markdown
    au BufNewFile,BufRead *.md                  setlocal ft=markdown

    " Common
    au BufWritePre * if &ft != "markdown" | :%s/\s\+$//ge | endif
    au BufReadPost *
    \ if line("'\"") > 0 && line ("'\"") <= line("$") |
    \   exe "normal! g'\"" |
    \ endif
augroup END
