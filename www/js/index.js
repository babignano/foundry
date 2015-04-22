(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

var location = require("./location");

window.app = (function() {

    alert("Code running");

    var initialize,
        bindEvents,
        onDeviceReady,
        render;

    // Application Constructor
    initialize = function() {
        alert("init");
        bindEvents();
    };

    // Bind Event Listeners
    //
    // Bind any events that are required on startup. Common events are:
    // 'load', 'deviceready', 'offline', and 'online'.
    bindEvents = function() {
        alert("Bind events");
        document.addEventListener('deviceready', onDeviceReady, false);
    };

    // deviceready Event Handler
    //
    // The scope of 'this' is the event. In order to call the 'receivedEvent'
    // function, we must explicitly call 'app.receivedEvent(...);'
    onDeviceReady = function() {
        alert("R1 ender running");
        location.getUsersLocation(render);
    };

    render = function(position) {

        alert("Render running");

        var mapElem = document.getElementById("map");

        // full size of screen
        mapElem.style.width = window.innerWidth + "px";
        mapElem.style.height = (window.innerHeight - 140) + "px";

        // this is where the custom code will go for each mapping implementation
            var mapOptions = {
                center: {
                    lat: -34.397,
                    lng: 150.644
                },
                zoom: 8
            };
            var map = new google.maps.Map(document.getElementById('map'), mapOptions);
    
    };

    return {
        initialize: initialize
    };

}());
},{"./location":2}],2:[function(require,module,exports){
module.exports = (function () {

    var getUsersLocation,
        onSuccess,
        onError;

    // onSuccess Geolocation
    //
    onSuccess = function (position) {
        var element = document.getElementById('geolocation');
        element.innerHTML = 'Latitude: '           + position.coords.latitude              + '<br />' +
                            'Longitude: '          + position.coords.longitude             + '<br />' +
                            'Altitude: '           + position.coords.altitude              + '<br />' +
                            'Accuracy: '           + position.coords.accuracy              + '<br />' +
                            'Altitude Accuracy: '  + position.coords.altitudeAccuracy      + '<br />' +
                            'Heading: '            + position.coords.heading               + '<br />' +
                            'Speed: '              + position.coords.speed                 + '<br />' +
                            'Timestamp: '          + position.timestamp                    + '<br />';
    };

    // onError Callback receives a PositionError object
    //
    onError = function (error) {
        alert('code: '    + error.code    + '\n' +
              'message: ' + error.message + '\n');
    };

    getUsersLocation = function (callback) {

        alert("Get users location..");

        navigator.geolocation.getCurrentPosition(function (position) {
            callback(position);
            onSuccess(position);
        }, function (error) {
            callback(null);
            onError(error);
        });
    };

    return {
        getUsersLocation: getUsersLocation
    };

}());

},{}],3:[function(require,module,exports){
module.exports = (function () {

    var newMap;

    newMap = function () {

    };

    return {
        newMap: newMap
    };

}());

},{}]},{},[1,2,3]);
