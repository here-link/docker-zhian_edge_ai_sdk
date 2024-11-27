# -*- coding: utf-8 -*-
#import torch
from flask import Flask, request

import time
from collections import OrderedDict
import codecs
import os
from pathlib import Path
from flask import jsonify
from gevent import pywsgi
import requests
import time
import re
# 获取所有配置参数
app = Flask(__name__)
# 设置编码-否则返回数据中文时候-乱码
app.config['JSON_AS_ASCII'] = False  #防止中文乱码

headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.110 Safari/537.36'}
dir_name='/workspace/apiservice/imagedata'

def get_image_data(url):
    if not os.path.exists(dir_name):
        os.mkdir(dir_name)

    file_name = url.split('/')[-1]
    #print(file_name)
    #t1 = time.time()*1000
    response = requests.get(url, headers=headers)
    with open(dir_name + '/' + file_name, 'wb') as f:
        f.write(response.content)

    #t2 = time.time()*1000
    #t3 = t2 -t1
    #print('use: %s ms' %t3)
    return dir_name+'/'+file_name


def read_data_from_binary_file(file):
    list_data =[]
    str=''
    f = open(file, 'rb')
    f.seek(0, 0)
    while True:
        t_byte = f.read(1)
        if len(t_byte) == 0:
            break
        else:
            list_data.append("%.2X" % ord(t_byte))

    str += ''.join(list_data)
    #str += ' '.join(list_data)
    return str

@app.route('/')
def hello():
    return "Nice To Meet You!"

@app.route('/predict', methods=['GET'])
def predict():
    # 获取输入数据
    #file = request.files['image']
    #filepath = request.args['image']
    ver =''
    url = request.args['image']
    ver = request.args['version']
    #print(ver)
    options = {'BH124' : 1, 'BH125': 2, 'GH226' : 3, 'BH226' : 4, 'BH322' : 5, 'BH333' : 6, 'BH334' : 7, 'BH335' :8, 'BH338' : 9, 'BH341' : 10, 'BH336' : 11, 'v2' : 12, 'V2' : 13}
    options1 = {'BH262' : 1, 'BH263': 2, 'BH413' : 3, 'BH414' : 4, 'BH415' : 5, 'BH416' : 6, 'BH417' : 7, 'BH418' :8, 'BH419' : 9, 'BH421' : 10, 'BH422' : 11, 'v3' : 12, 'V3' : 13}
    if ver in options:
        ver = 'v2'
    #elif ver == 'v3' or ver == 'BH262' or ver == 'BH263' or ver == 'BH413'or ver == 'BH414' or ver == 'BH415':
    elif ver in options1:
        ver = 'v3'
    else:
        te = re.findall('BH4', ver)
        te2 = re.findall('BH26', ver)
        if te:
            ver = 'v3'
        elif te2:
            ver = 'v3'
        else:
            ver = ''

    #if ver == 'v2' or ver == '' or ver == 'BH124'
    #print('ver==%s'%ver)
    #find path tag
    httptag = url.find('http', 0, 4)
    #print(url.find('http', 0, 4))
    pathtag = url.find('/', 0, 1)
    #print(url.find('/', 0, 1))
    #print(url)
    #download image
    if httptag ==0:
        filepath = get_image_data(url)
    else:
        filepath = url
    #print(filepath)
    emsg='success'
    binhex =''
    code = 1
    binfile = filepath+'_fixed.bin'
    my_file = Path(filepath)
    if my_file.exists():
        #check fm.bin exit
        #bin_file = Path(binfile)
        #if bin_file.exists():
        a = 0
        if a == 1:
            code = 0
            binhex = read_data_from_binary_file(binfile)
        else:
            # call api
            if not ver:
                #print('not ver')
                command ='/workspace/doorlock -i ' + filepath + ' -o fixed'
                #command ='/workspace/doorlock -i ' + filepath + ' -P ' + ver + ' -o fixed'
            else:
                #print('ver:%s'%ver)
                command ='/workspace/doorlock -i ' + filepath + ' -P ' + ver + ' -o fixed'
                #command ='/workspace/doorlock -i ' + filepath + ' -o fixed'

            #print(command)
            result = os.system(command)
            #print(result)

            # check file bin
            binfile = filepath+'_fixed.bin'
            bin_file = Path(binfile)
            if bin_file.exists():
                # read bin file
                code = 0
                binhex = read_data_from_binary_file(binfile)
            else:
                code = 1
                binhex = ''
                emsg='generate fm error'

    else:
        emsg='input file not find'


    # API 结果封装
    dict_list = []
    result = {'data': binhex}
    dict_list.append(result)

    #return result
    result = OrderedDict(code=code, codemsg=emsg, datamsg=dict_list)
    return jsonify(result)

if __name__ == '__main__':
    # curl -X POST -F file=@cat_pic.jpeg http://localhost:5000/predict
    #app.run(host='0.0.0.0', port=8008)
    server = pywsgi.WSGIServer(('0.0.0.0', 8008), app)
    server.serve_forever()